# OpenAI Model Registry & Responses API Migration

## Goal

Replace the static/regex-filtered OpenAI model list with a persistent database-backed registry that discovers models from the API, probes each one for text generation and judging capability, and serves the results to form dropdowns without runtime API calls. Migrate OpenAI generation from Chat Completions API to Responses API.

## Architecture

Three new components:

1. **`completion_kit_models` table** — persistent registry of discovered models with probe results
2. **`ModelDiscoveryService`** — discovers models from provider APIs, reconciles with DB, probes new models
3. **OpenAiClient Responses API migration** — switch `generate_completion` from `/v1/chat/completions` to `/v1/responses`

Forms read from the DB. No API calls at render time.

## Database: `completion_kit_models`

| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `provider` | string, not null | "openai", "anthropic", "llama" |
| `model_id` | string, not null | e.g. "gpt-5.4-mini" |
| `display_name` | string | e.g. "GPT-5.4 Mini" |
| `status` | string, not null | "active", "retired", "failed" |
| `supports_generation` | boolean | null = not probed yet |
| `supports_judging` | boolean | null = not probed yet |
| `generation_error` | text | error from generation probe |
| `judging_error` | text | error from judging probe |
| `probed_at` | datetime | last probe timestamp |
| `discovered_at` | datetime | first seen from API |
| `retired_at` | datetime | when model disappeared from API |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Unique index on `[provider, model_id]`.

### Statuses

- **active** — discovered from API, available for use
- **retired** — previously active, no longer returned by API. Not offered for new prompts/runs but still referenced by existing ones.
- **failed** — discovered but failed all probes. Not offered in dropdowns.

## Discovery & Probing Flow

**Triggers:**
- After saving a `ProviderCredential` (automatic)
- Manual "Refresh models" button on Settings page

**Step 1 — Discovery:** Call the provider's model list API. For OpenAI: `GET /v1/models`.

**Step 2 — Reconcile with DB:**
- Models in API but not in DB → create as `active` with `supports_generation: nil`, `supports_judging: nil`, set `discovered_at`
- Models in API and DB → no change (update `display_name` if different)
- Models in DB as `active` but not in API → mark `retired`, set `retired_at`

**Step 3 — Probe new models** (those with `supports_generation: nil`):

- **Generation probe:** `POST /v1/responses` with `model`, `input: "Say hello"`, `max_output_tokens: 10`. Success (200 with text output) → `supports_generation: true`. Error → `supports_generation: false`, save error in `generation_error`.
- **Judging probe:** Only if generation passed. Send a structured request asking for `Score: N\nFeedback: ...` format. If response contains parseable Score/Feedback → `supports_judging: true`. Otherwise → `supports_judging: false`, save error in `judging_error`.
- Set `probed_at` after probes complete.

**Step 4 — Done.** Registry is populated and classified.

Discovery + probing runs synchronously. The model list is small and probes use tiny requests.

### Service: `ModelDiscoveryService`

```
ModelDiscoveryService.new(provider: "openai", config: {...})
  .refresh!
```

Orchestrates discovery, reconciliation, and probing. One public method: `refresh!`.

## Responses API Migration (OpenAI only)

**OpenAiClient#generate_completion** changes from Chat Completions to Responses API.

Request:
```json
{
  "model": "gpt-5.4-mini",
  "input": "user prompt text",
  "instructions": "You are a helpful assistant.",
  "max_output_tokens": 1000,
  "temperature": 0.7
}
```

Endpoint: `POST /v1/responses`

Response: extract text content from `output` array.

**JudgeService** is unchanged — it calls `generate_completion` which handles the API format.

**AnthropicClient and LlamaClient** are unchanged.

## Form Dropdowns

**Prompt form (generation model):**
```ruby
CompletionKit::Model.where(status: "active", supports_generation: true)
```

**Run form (judge model):**
```ruby
CompletionKit::Model.where(status: "active", supports_judging: true)
```

**Editing existing prompt/run with a retired model:** The dropdown shows active models plus the currently-selected retired model with "(retired)" appended to its display name.

**Empty registry:** Show "No models available" with a link to Settings.

No API calls at render time.

## Retired Model Handling

Prompts and runs store model IDs as strings. When a model is retired:
- It disappears from "new" dropdowns
- Existing prompts/runs keep their stored model ID
- If someone re-runs a prompt with a retired model, it fails at the API with a clear error (already surfaced in the UI)
- Editing a prompt with a retired model shows it in the dropdown marked "(retired)" — user must pick an active model to save

## Testing

- **Discovery:** Mock OpenAI `/v1/models`, verify models created in DB
- **Reconciliation:** Seed DB, mock API with subset, verify retired models
- **Generation probe:** Mock `/v1/responses` success/failure, verify flag
- **Judging probe:** Mock `/v1/responses` with parseable/unparseable output, verify flag
- **Refresh trigger:** Saving ProviderCredential triggers discovery
- **Form filtering:** Prompt form shows generation-capable only, run form shows judge-capable only
- **Retired model in form:** Editing prompt with retired model shows it marked
- **OpenAiClient:** New Responses API request/response format

## Scope

- Registry table supports all providers but discovery/probing only implemented for OpenAI
- Anthropic continues using dynamic `/v1/models` API (can be migrated to registry later)
- Llama stays as-is
