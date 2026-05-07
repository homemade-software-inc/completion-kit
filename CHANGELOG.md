# Changelog

All notable changes to CompletionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.2] - 2026-05-06

### Added

- **Provider page: structured available-models table.** Each model is a row
  with the name, a green ✓ for generation support, and a green ✓ for judging
  support. Replaces the previous chip-cluster which made it hard to scan
  capabilities. Collapsed by default; auto-expands during a refresh and for
  about a minute after one completes. Header has hover-tooltips on the Gen
  and Judge columns explaining what they mean.
- **Live-updating models table during discovery.** As each model finishes
  probing, the table re-renders in place via Turbo Streams + morph (so the
  spinning refresh button keeps animating across renders). Refresh button
  spins and disables itself while a refresh is running.
- **Worker code auto-reload in development.** `bin/jobs` now wraps each job
  execution in `Rails.application.reloader` instead of the bare executor, so
  changes to job/service code are picked up without restarting the worker.
  Production keeps the lighter `Rails.application.executor`.
- **Smarter model re-probing.** Models that previously failed with a 4xx
  error other than 429 (e.g., a `tts-1` returning "You can't sample from
  this model") are no longer re-probed on every refresh. Models that failed
  with transient errors (5xx, timeouts, "Empty response", 429) ARE re-probed.
  Newly-discovered models are always probed once.
- **Per-row Retry on failed responses.** Failed rows in a run now have a
  `Retry` button on the right, scoped to just that row, alongside the
  bulk "Retry N failed rows" button in the run status panel.

### Changed

- **Run page status redesign.** Status indicator promoted to a proper
  colored pill in the page header (`● COMPLETED`, `● RUNNING`, etc.) with
  glow + animation matching the state. Generation/judging counters and the
  bulk retry button moved to a dedicated status panel above the responses
  list, styled as an instrument-panel strip.
- **Judged counters now track fully-reviewed rows**, not individual metric
  reviews. So `Judged 3/100` reads as "3 rows fully scored" instead of "3
  metric reviews complete (which might be 1 row of 3 metrics)". A row counts
  as `judged_failed` if any of its metric reviews failed.
- **Response detail page metadata uses the same config-table layout as the
  run page.** Run, Prompt, Dataset, Model, Judge as labeled rows instead of
  the inline `PROMPT … · DATASET …` line.
- **OpenAI probes now find the message item in the Responses output array.**
  Reasoning models (gpt-5*, o1*, o3*) return multi-item output where the
  first item is a `reasoning` chunk and the message comes later. The probe
  used to read `output[0].content[0].text` blindly and got nil for all
  reasoning models. Now it does `output.find { |o| o["type"] == "message" }`.
  This was the root cause of GPT-5.5 / GPT-5.5 Pro never being eligible as
  judges.
- **OpenAI probes use minimal/low reasoning effort when supported**, with a
  fallback to the model's default when the chosen effort isn't accepted
  (e.g., `gpt-5.5-pro` only allows `medium`/`high`). Probe budget bumped to
  65536 tokens and timeout to 180s for reasoning-class models.
- **OpenRouter and Ollama models now get judging-probed** via their
  OpenAI-compatible `/chat/completions` endpoints. Previously the probe
  router fell through to Anthropic's `/v1/messages` endpoint, so all
  OpenRouter and Ollama models were silently invisible as judges.
- **Auto-rename when saving as a new run.** If you edit a run with responses
  and don't change the name, the new run gets the next-incremented name
  (`#2`, `#3`, …) instead of inheriting the source run's name verbatim.
- **Engine routes are eagerly materialized before broadcast renders.** The
  worker process never serves an HTTP request, so Rails 8's lazy route set
  hadn't materialized engine URL helpers, causing `run_response_path`
  lookups to fail when a job called `broadcast_replace_to`. Touching
  `CompletionKit::Engine.routes.url_helpers` before render fixes it.
- **`Run#start!` writes a fresh `failure_summary`** on configuration errors
  ("LLM API not configured: …") and dataset-empty errors instead of only
  `error_message`, so the run page surfaces the right copy.
- **"Testing models" renamed to "Checking models"** in the discovery bar.
  "Fetching model list" renamed to "Looking up models". Friendlier wording.
- **Models card refresh button consolidated to one.** The previous version
  had duplicate refresh buttons (one in the form-card header, one in the
  disclosure summary). Now there's a single button next to the timestamp.
- **Provider edit page: discovery progress bar moved inside the Available
  models panel** instead of sitting above it, so the panel reads as a
  single coherent unit.

### Fixed

- **Worker process Turbo broadcasts could fail with `undefined method
  'run_response_path'`** when rendering response_row partials from a job
  context. Fixed by materializing engine URL helpers before each render.
- **Refresh button animation was lost on every Turbo Stream re-render** of
  the models card. Fixed by switching the broadcast from `replace` to
  `morph`, which preserves DOM identity and lets the CSS animation continue.
- **Per-row Retry button on failed responses was rendering on its own line
  beneath the row** because `<button_to>` was nested inside `<link_to>`
  (form-inside-anchor — invalid HTML, browsers hoist it out). Failed rows no
  longer wrap in `link_to`; they're plain `<div>` containers with the Retry
  button in the right column.
- **Available models help-text tooltip inherited the surrounding uppercase
  letter-spaced styling.** `.ck-info-popup` now explicitly resets
  `text-transform`, `letter-spacing`, `font-family`, `font-weight`, and
  `text-align` so help text always reads as normal sentence case.
- **Refresh on the provider page closed the available-models panel** because
  the re-rendered partial defaulted to collapsed. Panel now stays open while
  `discovery_status == "discovering"` and for 1 minute after `completed`.

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
