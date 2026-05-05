# Prompt Run Robustness, Concurrency, and Per-Row Failure Recovery

**Goal:** Make prompt runs robust to flaky LLM provider calls, durable across deploys, and capable of running in parallel without crowding each other or the host. Surface provider-side failures clearly so users can tell when an error is the provider's fault, not CompletionKit's.

This is the v2 follow-on to `2026-03-26-async-runs-design.md`, which explicitly deferred per-row retries and intra-run parallelism.

---

## Current Behavior

`Run#generate_responses!` and `Run#judge_responses!` each loop through their work synchronously inside a single ActiveJob (`GenerateJob`, `JudgeJob`). The queue adapter is `:async` in both `production.rb` and `development.rb`.

Failure modes today:

- A single `Faraday::Error` mid-loop flips the entire run to `failed`, throwing away every successful row that came before it. The user's only recourse is to click Generate again, re-spending every successful API call.
- `:async` jobs run in the web Puma's thread pool. A deploy or restart kills any in-flight run silently with no resumption.
- Solid Queue's schema is in `standalone/db/schema.rb` (migration `20260327200001_create_solid_queue_tables.rb`) but no code uses it.
- Concurrent runs share the in-process thread pool with no per-provider throttle, so two large simultaneous runs can trip provider rate limits.
- The `Run#status` enum (`pending → generating → judging → completed/failed`) treats generation and judging as strict sequential phases; judging cannot start until every row has finished generating, even though nothing forces this ordering.

---

## New Behavior

### Job topology

Each run fans out into row-level jobs that interleave generation and judging:

```
RunsController#generate
        │
        ▼
GenerateRowJob(run_id, row_index)          ──┐ N of these per run
   ├─ calls LLM → updates Response             │ (one per dataset row)
   ├─ on success: enqueues JudgeReviewJob      │
   │   for each metric on this run             │ each retried independently
   └─ on terminal failure: marks Response      │ via ActiveJob retry_on
       failed with provider error context    ──┘

JudgeReviewJob(response_id, metric_id)     ──┐ N×M of these per run
   ├─ calls judge LLM                          │
   └─ updates Review                         ──┘

Each job, on completion (success OR terminal failure):
   ├─ broadcasts its row/review update
   └─ enqueues RunCompletionCheckJob(run_id)

RunCompletionCheckJob(run_id)
   └─ if no outstanding work for run → run.mark_completed!
```

There is no phase wait. The `JudgeReviewJob`s for row 1 can run while `GenerateRowJob` for row 99 is still queued. A run is "done" when every `Response` is in a terminal state (`succeeded` or `failed`) and every expected `Review` is in a terminal state.

### Run status model

The status enum collapses to:

```
pending ──(user clicks Generate)──> running ──(all rows + reviews terminal)──> completed
                                       │
                                       └──(infra-level failure: dataset empty,
                                           judge unconfigured, etc.)──> failed
```

`generating` and `judging` are dropped. Per-row LLM-call failures **never** flip the run to `failed`; only terminal infra problems (no rows in dataset, missing judge model when judging requested, etc.) do.

### Failure semantics

- Each row's `GenerateRowJob` retries transient errors independently with backoff. After exhaustion, the row's `Response` is marked `status: "failed"` with provider error context recorded.
- Each `JudgeReviewJob` does the same for its `Review`.
- The run continues regardless of how many rows fail.
- When the run reaches a terminal state with any failed rows, the status header surfaces a `Retry failed rows` action that re-enqueues only the failed work.

### Provider error visibility

When a row fails, the `Response` row in the UI displays a badge leading with the provider name and the provider's status / error class:

```
Failed: OpenAI 429 — Rate limit exceeded
Failed: Anthropic 529 — Overloaded
Failed: OpenAI Faraday::TimeoutError — Connection reset by peer
```

This makes it immediately obvious to the user that the failure originated at the provider, not in CompletionKit. Hover/click expands to the full error message and attempt count.

### Concurrency

Solid Queue concurrency keys cap parallel work along two independent dimensions:

- **Per-provider** (`limits_concurrency key: -> { "llm:#{provider}" }`) — cap simultaneous LLM calls to a single provider system-wide. Default 10. Stops a 429 storm.
- **Per-run** (`limits_concurrency key: -> { "run:#{run_id}" }`) — cap simultaneous calls from a single run. Default 5. Stops one large run from monopolizing the per-provider budget when other runs are queued.

Both limits are ENV-configurable so they can be tuned without a deploy:

| Var | Default | Purpose |
|-----|---------|---------|
| `COMPLETION_KIT_LLM_CONCURRENCY` | 10 | Max in-flight calls per provider |
| `COMPLETION_KIT_PER_RUN_CONCURRENCY` | 5 | Max in-flight calls per run |
| `SOLID_QUEUE_THREADS` | 10 | Worker thread pool (must be ≥ `COMPLETION_KIT_LLM_CONCURRENCY`) |
| `SOLID_QUEUE_PROCESSES` | 1 | Bump only if vertical scaling fails |

Generation and judging keep separate per-provider buckets — judging GPT-4 outputs with Claude does not contend with the generation pool because the provider keys differ.

A boot-time check logs a warning if `SOLID_QUEUE_THREADS < COMPLETION_KIT_LLM_CONCURRENCY`, since threads would become the actual bottleneck and the per-provider cap would never be reached.

### Retry policy

```ruby
class GenerateRowJob < ApplicationJob
  queue_as :llm

  retry_on Faraday::TimeoutError,
           Faraday::ConnectionFailed,
           wait: :polynomially_longer, attempts: 5

  retry_on CompletionKit::RateLimitError,
           wait: ->(executions) { 30 * executions }, attempts: 5

  discard_on ActiveJob::DeserializationError
  discard_on CompletionKit::ConfigurationError
end
```

A new `CompletionKit::RateLimitError` is raised by `LlmClient` when the provider returns 429. Rate limits clear on a wall clock, so they get a fixed-step backoff (30s, 60s, 90s, 120s, 150s) instead of exponential.

`ActiveJob::DeserializationError` (response/review was deleted) and `CompletionKit::ConfigurationError` (missing API key, etc.) are not worth retrying and discard immediately.

A `rescue_from(StandardError)` on the job records terminal failure on the row, broadcasts, and enqueues the completion check.

### In-flight retry visibility

A `before_perform` increments the row's `attempts` counter and broadcasts a "retrying… attempt N/5" sub-status, so the UI shows the row pulsing through retries instead of looking stuck. After exhaustion, the row settles into `failed` with the final provider error visible.

### Progress UI

The status header on the run show page splits its progress into two counters (generation and judging), since the two phases interleave:

```
┌──────────────────────────────────────────────────────────────┐
│ ● Running                                                    │
│   Generated 47/100 ████████░░░░░░░░░░ (3 failed)             │
│   Judged    38/200 ████░░░░░░░░░░░░░░ (1 failed)             │
│                                                              │
│   [Retry 4 failed rows]                                      │
└──────────────────────────────────────────────────────────────┘
```

When complete:

```
┌──────────────────────────────────────────────────────────────┐
│ ✓ Completed · avg score 7.2                                  │
│   100/100 generated · 196/200 judged · 4 failed              │
│   [Retry 4 failed rows]                                      │
└──────────────────────────────────────────────────────────────┘
```

A `Run#progress_snapshot` method returns a single hash:

```ruby
{ generated_done:, generated_total:, generated_failed:,
  judged_done:, judged_total:, judged_failed: }
```

so the partial reads from one source of truth.

### Response row UI

Per-row chrome on the responses table:

- **Pending** — spinner + "queued"
- **Retrying** — spinner + "retrying… attempt 3/5" (subtle yellow tint)
- **Succeeded** — response text + reviews as today
- **Failed** — red badge `OpenAI 429 — Rate limit exceeded`, hover/click expands to full message, per-row `Retry` link

### Turbo Stream broadcasts

Channel stays `completion_kit_run_<id>`. Targets that get replaced:

| Event | Targets |
|-------|---------|
| `GenerateRowJob` start | `response_<id>` |
| `GenerateRowJob` succeeded | `response_<id>`, `run_status_header` |
| `GenerateRowJob` failed | `response_<id>`, `run_status_header` |
| `JudgeReviewJob` succeeded/failed | `review_<id>`, `run_status_header` |
| `Run` completed | `run_status_header`, `run_actions`, `run_sort_toolbar` |

### Race-free completion check

`RunCompletionCheckJob` is enqueued at the end of every row/review job rather than handled inline. It runs `if run.outstanding_work_zero? then run.mark_completed!`. Solid Queue's `concurrency_key: "run:<id>:completion", limit: 1` serializes these checks so two near-simultaneous "am I last?" jobs cannot both decide they are.

This costs one tiny extra job per row/review completion in exchange for a clean race-free completion transition without row-level locking.

### Retry-failed-rows action

A new `RunsController#retry_failures` action:

1. Resets failed `Response`s to `pending` (clears error fields, resets `attempts` to 0 — UI reads "attempt N/5" so attempts must be a per-cycle counter, not a lifetime one)
2. Resets dependent failed `Review`s the same way
3. Re-enqueues `GenerateRowJob` for the reset responses' indices
4. Run goes back to `running`

REST API equivalent: `POST /api/v1/runs/:id/retry_failures`.

### JSON API

`Run#as_json` keeps backward compatibility:

- `progress_current` / `progress_total` keep their existing meaning, mapped to `generated_done` / `generated_total`.
- New `progress` object: `{ generated: { done, total, failed }, judged: { done, total, failed } }`.
- New `failed_response_ids` array.
- New endpoint: `POST /api/v1/runs/:id/retry_failures`.

### Deployment

Render currently runs the standalone app as a single Web service, configured via the Render dashboard (no `render.yaml` exists in the repo). A new Background Worker service is added manually:

1. Render dashboard → New service → Background Worker
2. Same repo, same branch, same root directory as web
3. Build command: `bundle install`
4. Start command: `cd standalone && bin/jobs`
5. Env vars: copy the entire web service env-var set, then add `SOLID_QUEUE_THREADS=10`, `COMPLETION_KIT_LLM_CONCURRENCY=10`, `COMPLETION_KIT_PER_RUN_CONCURRENCY=5`. The worker must have the same `DATABASE_URL`, `RAILS_MASTER_KEY`, all LLM provider keys, and the three `COMPLETION_KIT_ENCRYPTION_*` keys — without those last three the worker crashes on boot when the initializer touches `ProviderCredential` rows.
6. No pre-deploy on the worker. Migrations run from the web service's pre-deploy.

Solid Queue tables already exist in production (migration `20260327200001_create_solid_queue_tables.rb` is committed and applied). No DB work is needed beyond the schema additions in this spec.

`config/environments/production.rb` flips `config.active_job.queue_adapter` from `:async` to `:solid_queue`. Same change in `development.rb` so dev parity matches prod (`bin/dev` Procfile gets a `worker: bin/jobs` line).

### Observability

Mount `mission_control-jobs` at `/jobs` behind the engine's existing auth so queue health is inspectable without SSH. Optional but cheap.

### In-flight runs at the cutover

Any run still mid-flight under `:async` is killed by the deploy that switches adapters. A one-time Rake task (`completion_kit:mark_interrupted_runs_failed`) run in the deploy hook marks `running` runs as `failed` with `failure_summary: "Interrupted by deploy"`, so users can hit Retry and rerun cleanly. One-time cost; only affects runs in flight at the cutover.

---

## Schema Changes

### `completion_kit_responses`

```ruby
add_column :completion_kit_responses, :status, :string, default: "pending", null: false
add_column :completion_kit_responses, :error_provider, :string
add_column :completion_kit_responses, :error_class, :string
add_column :completion_kit_responses, :error_status, :integer
add_column :completion_kit_responses, :error_message, :text
add_column :completion_kit_responses, :attempts, :integer, default: 0, null: false
add_column :completion_kit_responses, :row_index, :integer
add_index  :completion_kit_responses, [:run_id, :status]
```

Backfill: existing responses with `response_text` present get `status: "succeeded"`.

### `completion_kit_reviews`

```ruby
add_column :completion_kit_reviews, :status, :string, default: "pending", null: false
add_column :completion_kit_reviews, :error_provider, :string
add_column :completion_kit_reviews, :error_class, :string
add_column :completion_kit_reviews, :error_status, :integer
add_column :completion_kit_reviews, :error_message, :text
add_column :completion_kit_reviews, :attempts, :integer, default: 0, null: false
add_index  :completion_kit_reviews, [:response_id, :status]
```

Backfill: existing reviews with `ai_score` present get `status: "succeeded"`.

### `completion_kit_runs`

```ruby
add_column :completion_kit_runs, :failure_summary, :string
```

Status enum becomes `pending | running | completed | failed` (drop `generating`, `judging` from `STATUSES` constant). Existing rows with `generating` or `judging` are migrated to `running`; existing `progress_current` / `progress_total` columns are kept and used for the legacy generated counter.

---

## Files to Create

```
app/jobs/completion_kit/generate_row_job.rb
app/jobs/completion_kit/judge_review_job.rb
app/jobs/completion_kit/run_completion_check_job.rb
(retry_failures action lives inline in RunsController; no new file)
app/views/completion_kit/runs/_status_header.html.erb (rewrite)
app/views/completion_kit/runs/_response_row.html.erb (rewrite)
app/services/completion_kit/rate_limit_error.rb (new exception class)
config/queue.yml
db/migrate/<timestamp>_add_status_and_error_to_responses.rb
db/migrate/<timestamp>_add_status_and_error_to_reviews.rb
db/migrate/<timestamp>_add_failure_summary_to_runs.rb
lib/tasks/completion_kit_runs.rake (mark_interrupted_runs_failed task)
```

## Files to Modify

```
app/models/completion_kit/run.rb
  - shrink generate_responses!/judge_responses! to start! that creates pending Responses + enqueues GenerateRowJobs
  - drop status enum values, add progress_snapshot, add outstanding_work_zero?, add mark_completed!
  - update broadcasts to fire from job callbacks rather than the loop
app/models/completion_kit/response.rb
  - add status enum + error fields, validations, terminal? predicate
app/models/completion_kit/review.rb
  - same shape as response
app/models/completion_kit/prompt.rb
  - add llm_model_provider method ("openai" / "anthropic" / etc., from llm_model)
app/services/completion_kit/llm_client.rb
  - raise RateLimitError on 429
app/jobs/completion_kit/generate_job.rb (delete or repoint to GenerateRowJob enqueuer)
app/jobs/completion_kit/judge_job.rb (delete or repoint)
app/controllers/completion_kit/runs_controller.rb
  - generate action calls run.start! instead of GenerateJob.perform_later
  - add retry_failures action
app/controllers/completion_kit/api/v1/runs_controller.rb
  - same change + new retry_failures endpoint
config/routes.rb
  - POST /runs/:id/retry_failures (web + api/v1)
config/environments/production.rb
  - config.active_job.queue_adapter = :solid_queue
config/environments/development.rb
  - same
standalone/Procfile.dev (or bin/dev) — add worker process line
```

## Dependencies

```
gem "solid_queue"           # add to standalone/Gemfile
gem "mission_control-jobs"  # optional, add to standalone/Gemfile, for /jobs dashboard
```

The `solid_queue_*` tables already exist in `standalone/db/schema.rb` (migration `20260327200001_create_solid_queue_tables.rb`) but the gem itself is not in any Gemfile — someone committed the migration ahead of the gem. The plan adds the gem to `standalone/Gemfile` (the engine itself stays adapter-agnostic and does not depend on Solid Queue).

---

## Rollout

Three PRs, ordered to avoid downtime:

1. **PR 1 — schema + status backfill.** Migrations for `status` / error columns on responses and reviews, `failure_summary` on runs. Backfill existing rows. No behavior change. Safe to ship to web only.

2. **PR 2 — adapter switch + new jobs.** Add `config/queue.yml`, create the row-level jobs and `RunCompletionCheckJob`, refactor `Run` to enqueue per-row work, switch `production.rb` adapter to `:solid_queue`. **The Render Worker service must exist before this ships** or no jobs will run. Run the `mark_interrupted_runs_failed` task in the deploy hook to clean up any runs in flight at the cutover.

3. **PR 3 — UI + API.** Status header rewrite, response row rewrite, retry-failures action, `/api/v1/runs/:id/retry_failures` endpoint, JSON API extensions. Schema is already in place from PR 1.

---

## Out of Scope

- Multi-run dashboard / cross-run progress view (current per-run page is sufficient per user's stated needs).
- Cancel a running job mid-execution.
- Per-row retry budget tuning. The 5-attempt cap is hardcoded in this spec; revisit if rate-limit storms become routine.
- Render Blueprint (`render.yaml`) adoption — flagged as a separate follow-up so deployment isn't lore.
- A separate `failed_with_warnings` run state — partial-failure runs land on `completed` and surface failure counts in the header.

---

## Follow-ups (not part of this work)

- Update `project_render_runbook.md` memory entry: queue adapter is `:solid_queue`, drop the "restart to clear stuck async thread pool" note, document the worker service.
- Consider adopting `render.yaml` Blueprint so worker config is committed alongside the code.
