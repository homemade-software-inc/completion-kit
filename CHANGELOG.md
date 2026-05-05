# Changelog

All notable changes to CompletionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-05-05

### Fixed

- **Live UI updates were broken on the run show page in 0.4.0.** The standalone
  shipped with `cable.yml` set to the `:async` ActionCable adapter, which only
  delivers messages within the same process. Once 0.4.0 moved generate/judge
  jobs into a separate `bin/jobs` worker process, the broadcasts those jobs
  emit became invisible to browser subscribers connected to the web process —
  the page would show pending rows forever even though the worker was
  successfully processing them. Adds `solid_cable` to the standalone's
  Gemfile, configures `cable.yml` to use it in development and production,
  and ships a migration for the `solid_cable_messages` table. After
  upgrading: `cd standalone && bundle install && bin/rails db:migrate`.

## [0.4.0] - 2026-05-05

### Added

- Per-row prompt-run jobs (`GenerateRowJob`, `JudgeReviewJob`) with independent
  retry on transient LLM failures (`Faraday::TimeoutError`,
  `Faraday::ConnectionFailed`, polynomial backoff) and rate limits
  (`CompletionKit::RateLimitError`, fixed 30s × N backoff). One bad row no
  longer kills the whole run.
- Generation and judging interleave automatically: each successful row
  enqueues its `JudgeReviewJob`s immediately rather than waiting for the
  whole batch.
- `Run#progress_snapshot` returns six counters (`generated_done/total/failed`,
  `judged_done/total/failed`); status header surfaces both.
- `POST /runs/:id/retry_failures` (web + `/api/v1/runs/:id/retry_failures`)
  re-enqueues only failed rows. Per-row Retry button on each failed response.
- Per-row provider error context: failed rows show
  `Failed: OpenAI 429 — Rate limit exceeded` so users can tell when a failure
  is the provider's fault, not CompletionKit's.
- New error classes: `CompletionKit::Error`, `CompletionKit::ConfigurationError`,
  `CompletionKit::RateLimitError(provider:, status:, retry_after:)`.
- All four LLM clients (`OpenAiClient`, `AnthropicClient`, `OllamaClient`,
  `OpenRouterClient`) raise `RateLimitError` on 429 and re-raise
  `Faraday::Error` so retries actually fire.
- `ModelDiscoveryJob` hardened with the same retry policy.
- `CompletionKit::WorkerHealth.healthy?` and a banner on running runs when
  no Solid Queue worker has heartbeated in 30s.
- `mission_control-jobs` dashboard mounts at `/jobs` in the standalone behind
  session auth.
- `Run#as_json` extended with `progress` object (`generated`/`judged`
  sub-objects with `done/total/failed`), `failed_response_ids`, and
  `failure_summary`. Legacy `progress_current` and `progress_total` keys
  preserved.
- `failure_summary` (text) on runs for infra-level failures (dataset empty,
  judge model unconfigured).
- `attempts`, `error_provider`, `error_class`, `error_status`, `error_message`,
  `row_index` columns on responses; same error/`attempts` shape on reviews.
- Compound indexes `[run_id, status]` on responses and `[response_id, status]`
  on reviews (created with `algorithm: :concurrently` on Postgres).

### Changed

- **Standalone deployment now requires a worker process.** The standalone
  switches from `:async` to `:solid_queue` for ActiveJob. Run
  `cd standalone && bin/jobs` alongside `bin/rails server` (or
  `foreman start -f Procfile.dev`). Without it, generate/judge runs sit at
  "running" forever — the new worker-health banner detects this.
- `Run::STATUSES` collapsed from `pending|generating|judging|completed|failed`
  to `pending|running|completed|failed`. Generation and judging now
  interleave so the separate phases stop making sense. Existing
  `generating`/`judging` rows are migrated to `running`.
- `Review::STATUSES`: `evaluated` renamed to `succeeded` for cross-model
  consistency. Existing rows backfilled.
- The standalone DB pool is sized dynamically to fit Solid Queue's thread
  count (`pool: max(RAILS_MAX_THREADS, SOLID_QUEUE_THREADS + 2)`).
- The MCP `runs_judge` tool is removed — judging is now per-row automatic.
  Tool count: 35 → 34.

### Removed

- `Run#judge_responses!` and the standalone `judge` controller actions
  (web + API). The new per-row job topology supersedes them.
- The legacy monolithic `GenerateJob` and `JudgeJob`. Use `Run#start!` (which
  enqueues `GenerateRowJob` per row) and let judging chain automatically.

### New environment variables (standalone)

- `SOLID_QUEUE_THREADS` (default 10) — worker thread pool size.
- `SOLID_QUEUE_PROCESSES` (default 1) — worker process count.
- `COMPLETION_KIT_LLM_CONCURRENCY` (default 10) — soft global cap on
  simultaneous LLM calls; warns at boot if set higher than
  `SOLID_QUEUE_THREADS`.
- `COMPLETION_KIT_PER_RUN_CONCURRENCY` (default 5) — max simultaneous LLM
  calls from a single run.

### Migration notes

- `bin/rails db:migrate` applies five new migrations (responses error
  columns + concurrent index; reviews error columns + concurrent index;
  runs `failure_summary`).
- A one-time `completion_kit:mark_interrupted_runs_failed` rake task is
  available if you have runs in flight at the adapter cutover. Most
  installations won't need it.

## [0.3.0] - 2026-04-25

### Changed

- **License:** CompletionKit 0.3.0 and later are licensed under the Business
  Source License 1.1 with a 3-year Change Date to GPL v3. You may use
  CompletionKit freely for any purpose — including production — except to
  offer it to third parties as a hosted or managed service whose primary
  value is CompletionKit itself. Versions 0.2.x and earlier remain
  MIT-licensed and are unaffected; anyone relying on MIT can pin to 0.2.x.
  See `LICENSE` for full terms and the Additional Use Grant.

### Fixed

- Includes the migration idempotency fix from 0.2.1.

## [0.2.0] - 2026-04-22

### Added

- Optional `tenant_scope` / `tenant_scope_columns` config hooks for multi-tenant host apps. No behavior change when unset.

## [0.1.0] - 2026-04-18

### Changed

- **Breaking:** `Criteria` renamed to `Metric Group` across the entire product.
  REST API paths `/api/v1/criteria` → `/api/v1/metric_groups`. MCP tools
  `criteria_*` → `metric_groups_*`. Ruby class `CompletionKit::Criteria` →
  `CompletionKit::MetricGroup`, `CompletionKit::CriteriaMembership` →
  `CompletionKit::MetricGroupMembership`. Web routes `/completion_kit/criteria` →
  `/completion_kit/metric_groups`. Database tables renamed in place; no
  data migration needed. No backwards-compatibility aliases.

### Removed

- **Breaking:** `evaluation_steps` column removed from the `Metric` model and
  all associated UI, REST API, and MCP tool surfaces. Scoring now relies on
  the metric's `instruction` and `rubric_bands` alone.

### Known limitations

- Standalone app uses the `:async` queue adapter (in-process only). Solid
  Queue migration is planned for 0.2.0.

## [0.1.0.rc1] - 2026-04-15

Release candidate 1 for 0.1.0. Published to RubyGems as
`completion-kit 0.1.0.rc1` for pre-release validation before cutting
the real 0.1.0.

Initial public release of CompletionKit, a Rails engine for testing and
evaluating GenAI prompts across multiple providers.

### Added

- **Prompts, Runs, Datasets, Metrics, and Criteria** — core models for
  defining prompts with variable placeholders, running them against CSV
  datasets, and scoring outputs with LLM judges against user-defined
  criteria.
- **Provider credentials** — encrypted storage for LLM API keys with
  auto-seeding from environment variables, masked display, and per-provider
  usage stats. Supports OpenAI, Anthropic, Ollama (or any OpenAI-compatible
  local endpoint), and OpenRouter.
- **Model discovery** — asynchronous fetching of available models per
  provider with real-time progress updates. OpenRouter and Ollama discovery
  trust the upstream API's model list and skip per-model probing, keeping
  discovery fast for providers that publish capability metadata.
- **REST JSON API** — Bearer token authenticated API exposing full CRUD
  for Prompts, Runs, Datasets, Metrics, Criteria, and ProviderCredentials;
  nested read-only Responses under Runs; and `POST /api/v1/runs/:id/generate`
  and `/judge` process actions that return `202 Accepted` for async
  processing.
- **MCP server** — 36 tools mirroring the REST API, exposing CompletionKit
  to agent clients via the Model Context Protocol. Install cards with
  one-click copy for Claude Code and other MCP-compatible clients.
- **Web UI** — session-based login, onboarding dashboard showing only
  remaining setup steps, prompt and run management, Turbo Stream live
  updates for run progress and response rows, and a progress bar partial.
  Model dropdowns are grouped by provider, with OpenRouter models split
  further by upstream namespace.
- **Background jobs** — `GenerateJob` and `JudgeJob` for async processing,
  with Solid Queue configured in the standalone app.
- **Suggestion history** — AI-assisted prompt improvement suggestions
  persisted to the database, tracked with applied status, and surfaced in
  the prompt UI for evolution history.
- **Temperature control** — per-run temperature slider with info tooltip
  (default 1.0).
- **Retry failed runs** — "Retry" action that only appears on failed runs.
- **Edit-as-new-run** — editing a run with existing responses creates a
  new run, preserving the original.
- **Judge input awareness** — judge is passed the input data so it can
  verify claims against the actual input, not just the output.
- **API reference page** — per-endpoint documentation with params,
  copy-to-clipboard examples, and MCP tab shown by default.
- **Standalone app** — bundled Rails app under `standalone/` for local
  development and self-hosting, with dotenv support and Active Record
  encryption for stored provider API keys.
- **CI/CD** — GitHub Actions workflow and Dependabot.
- **100% test coverage** — line and branch coverage enforced in CI across
  440+ RSpec examples.

[Unreleased]: https://github.com/homemade-software-inc/completion-kit/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.1.0.rc1...v0.1.0
[0.1.0.rc1]: https://github.com/homemade-software-inc/completion-kit/releases/tag/v0.1.0.rc1
