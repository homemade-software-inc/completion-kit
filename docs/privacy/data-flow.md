# LLM provider data flow, logging, and retention

A short, factual description of what the CompletionKit engine sends to model
providers, what it stores, what it logs, and what a host (such as
completion-kit-cloud) is responsible for. Audited against engine `0.5.32`.

## 1. What is sent to model providers

For every generation and every judge review the engine builds a Faraday HTTP
request to the configured provider. Today: OpenAI (`api.openai.com`),
Anthropic (`api.anthropic.com`), OpenRouter (`openrouter.ai`), and any
OpenAI-compatible endpoint configured under "Ollama" (default
`http://localhost:11434/v1`).

### Body

The request body carries:

- The **rendered prompt text**. For a generation, this is the prompt template
  with `{{variable}}` placeholders substituted from the dataset row. For a
  judge review, it is the system rubric plus the response under review.
- The **model id** (e.g. `gpt-4.1-mini`).
- **Generation parameters**: `max_tokens`, `temperature` (when supported by
  the model — some reasoning models silently drop it and the client retries
  without).

It does **not** carry:

- Any organisation slug, organisation id, user id, user name, user email, or
  IP address. The engine does not know about these — multi-tenant attribution
  lives in the host's tables.
- Any custom `User-Agent` rebranding or telemetry header.
- File attachments, vision inputs, or tool-call definitions (none of those
  surfaces exist in the engine yet).

### Headers

- The provider's API key is sent in the standard provider-specific header:
  `Authorization: Bearer …` for OpenAI/OpenRouter/Ollama-compatible,
  `x-api-key: …` (plus `anthropic-version`) for Anthropic.
- No additional identifying headers are added.

## 2. What is persisted in engine-owned tables for each run

See `docs/privacy/pii-inventory.md` for the full table-by-table inventory.
Summary of what a run produces:

| Stored where | Field | What it holds |
|---|---|---|
| `completion_kit_runs` | `name`, `judge_model`, `temperature`, `judge_temperature`, `max_tokens`, status / progress / error fields | Run metadata. |
| `completion_kit_responses` | `input_data`, `response_text`, `expected_output` | The dataset row for that response, the model's completion, and (optional) the reference answer. |
| `completion_kit_responses` | `error_class`, `error_message`, `error_provider`, `error_status` | Captured when a provider call fails. `error_message` is the truncated response body from the provider. |
| `completion_kit_reviews` | `ai_feedback`, `ai_score`, `metric_name`, `instruction` | The judge's verdict for one (response, metric) pair, plus the rubric instruction that was active at judge time. |
| `completion_kit_reviews` | `error_*` | Same captured-provider-error pattern as responses. |

Raw provider response payloads are **not** stored. The engine extracts the
text content from the JSON response and discards the rest.

### Retention

The engine does not run any retention job. Run data, response data, and
review data persist until the host or an operator deletes them. There is no
configurable TTL today. Hosts that need a retention policy implement it
themselves (a periodic job that deletes runs older than N days, for example).

### Tenant scoping

Vanilla engine rows have no tenant attribution. A host opts into multi-tenancy
through `CompletionKit.config.tenant_scope` and `tenant_scope_columns`, which
adds (host-supplied) tenant columns and the default scope at the model layer.
See `README.md#multi-tenant-host-apps-advanced`.

## 3. What ends up in `Rails.logger` and structured logs

- The provider clients do not log prompt text or response text at any level.
- Rails request logs go through `config.filter_parameters`. The standalone
  app's defaults (`standalone/config/initializers/filter_parameter_logging.rb`)
  filter `:passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :ssn, :cvv, :cvc`. The `_key` filter catches `api_key`, so a
  provider-credential form submit does not log the key.
- Provider API keys travel in HTTP headers (not request bodies). Faraday does
  not log headers by default; the engine does not enable Faraday's logging
  middleware. API keys do not appear in Rails logs.
- Backtraces: API keys are not interpolated into exception messages or
  rescue strings in the engine. Provider error responses are truncated and
  surfaced into the `response.error_message` / `review.error_message`
  columns, not the logger.

## 4. Error-tracker context (Honeybadger, Sentry, etc.)

The engine does **not** depend on any error-tracker gem. It reports through
the framework-level `Rails.error.report(...)` API in three places:

- `JudgeReviewJob` — `Rails.error.report(error, handled: true, context: { job:, run_id:, review_id: })`
- `GenerateRowJob` — `Rails.error.report(error, handled: true, context: { job:, run_id:, response_id: })`
- `McpController` — `Rails.error.report(e, handled: true, context: { controller: "CompletionKit::McpController" })`

The supplied context carries integer ids only, never prompt content, response
content, or API keys. If the host has Honeybadger / Sentry / Rollbar wired
into `Rails.error`, those trackers will see the exception, its backtrace,
and the context above — nothing more from the engine.

What the host should still check on its side:

- Whether its tracker is configured to attach the **HTTP request body** to
  error reports. A POST to the engine's REST API includes prompt or dataset
  content in the body; if the tracker captures bodies, that content reaches
  the tracker. The engine cannot prevent this — it is a tracker-config
  decision in the host.
- Whether its tracker is configured to attach **session / user attributes**.
  Same caveat.

## 5. BYO API keys

A customer-controlled key path exists end-to-end:

- `CompletionKit::ProviderCredential` is a per-workspace row that stores the
  provider, api_key, and optional api_endpoint. The `api_key` and
  `api_endpoint` columns are encrypted at rest via
  `ActiveRecord::Encryption` (see `app/models/completion_kit/provider_credential.rb`).
- The provider client (`LlmClient.for_provider`) prefers the value passed in
  the config, falling back to ENV. Hosts that drive credential selection by
  workspace pass the workspace's credential value into the client.
- The engine never logs, prints, or includes the key in error contexts.
- Provider terms of service apply to whoever owns the API key. With BYO keys,
  the contract is between the workspace and the provider, not the host and
  the provider.

## 6. Org-deletion cascade

Already covered in `docs/privacy/pii-inventory.md` §Survival semantics. Summary:

- Multi-tenant host: the host has added an `organization_id` (or equivalent)
  column to engine tables via its own migrations. Cascading the org delete to
  engine rows is the host's responsibility — typically one transactional
  purge filtered by the tenant column, run as part of the host's
  org-delete job.
- Single-tenant deploy: no org concept; engine rows persist until removed
  manually.

## Engine-side findings

| Concern | Status |
|---|---|
| Prompt / response content logged at any level | No |
| API keys reachable from logs or backtraces | No (header-only, not interpolated) |
| API keys redacted from request param logging | Yes (`_key` filter) |
| Raw provider response payloads stored | No (text is extracted, rest discarded) |
| Tracker context carries content | No (ids and class names only) |
| BYO-keys path | Yes, encrypted at rest, per-workspace |
| Automatic retention job | No (host responsibility) |
| Org-delete cascade | Host responsibility via `tenant_scope_columns` |

No engine code changes are required to close the data-flow concerns. The
remaining responsibilities — retention policy, org-delete cascade, and any
tracker-side request-body capture — belong to the host that mounts the engine.
