# Async Runs with Live Progress

**Goal:** Make generation and judging run as background jobs with per-response live updates streamed to the UI via Turbo Streams.

---

## Current Behavior

`Run#generate_responses!` and `Run#judge_responses!` are synchronous. The HTTP request blocks until all LLM calls complete. For a run with 50 rows, this can take minutes. The UI is unresponsive during this time.

---

## New Behavior

### Job System

- **Solid Queue** as the Active Job backend. Works with SQLite (dev) and Postgres (prod). No Redis.
- Two job classes: `GenerateJob` and `JudgeJob`, both under `CompletionKit`.
- When the user clicks "Generate" or "Judge", the controller enqueues the job and redirects immediately. No more blocking.

### Progress Tracking

The Run model tracks progress with two new columns:

- `progress_current` (integer, default 0) — how many items are done in the current phase
- `progress_total` (integer, default 0) — total items in the current phase

Status flow stays the same: `pending → generating → judging → completed` (or `failed`).

### Per-Response Processing

Generation and judging are refactored to process one response at a time, saving and broadcasting after each:

1. Job starts, sets status to `generating`, sets `progress_total` to row count, `progress_current` to 0
2. For each row: create the response, save it, increment `progress_current`, broadcast the update
3. If judge is configured, transition to `judging`, reset progress counters
4. For each response × metric: evaluate, save the review, increment `progress_current`, broadcast
5. Set status to `completed`

If any LLM call fails, the run transitions to `failed` but keeps all responses generated so far. No rollback.

### Live UI Updates (Turbo Streams)

**Solid Cable** as the ActionCable adapter (database-backed, no Redis).

Each run broadcasts to a Turbo Stream channel: `completion_kit_run_#{run.id}`.

Three types of broadcasts:

1. **Progress update** — replaces the progress bar/status area on the run show page
2. **New response** — appends a row to the responses table
3. **Review update** — replaces a response row when its review scores arrive

The run show page subscribes to the channel via `turbo_stream_from`.

### Progress UI

The run show page gets a progress section (visible when status is `generating` or `judging`):

- Phase label: "Generating responses..." or "Judging responses..."
- Progress bar: `progress_current / progress_total` with percentage
- Counter text: "12 of 50 responses generated"

This section is wrapped in a Turbo Frame that gets replaced on each broadcast.

### API Behavior

The REST API's `POST /api/v1/runs/:id/generate` and `/judge` change:

- They enqueue the job and return immediately with `202 Accepted` and the run's current state
- Callers poll `GET /api/v1/runs/:id` to check status and progress
- The `as_json` on Run includes `progress_current` and `progress_total`

---

## Files to Create

```
app/jobs/completion_kit/generate_job.rb
app/jobs/completion_kit/judge_job.rb
app/channels/completion_kit/run_channel.rb (if needed beyond turbo_stream_from)
app/views/completion_kit/runs/_progress.html.erb
```

## Files to Modify

```
app/models/completion_kit/run.rb — refactor to per-response processing, add progress columns, add broadcasts
app/controllers/completion_kit/runs_controller.rb — enqueue job instead of calling synchronously
app/controllers/completion_kit/api/v1/runs_controller.rb — return 202, enqueue job
app/views/completion_kit/runs/show.html.erb — add turbo_stream_from, progress section, live response table
db/migrate/ — add progress_current, progress_total to runs
config/routes.rb — (may need ActionCable mount if not auto-configured)
standalone/config/environments/production.rb — configure Solid Cable adapter
standalone/config/environments/development.rb — configure async or Solid Cable adapter
```

## Dependencies

```
gem "solid_queue" — Active Job backend
gem "solid_cable" — ActionCable adapter
gem "turbo-rails" — Turbo Streams (may already be available via Rails)
```

## Migration

```ruby
class AddProgressToRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :completion_kit_runs, :progress_current, :integer, default: 0
    add_column :completion_kit_runs, :progress_total, :integer, default: 0
  end
end
```

---

## Out of Scope

- Retry failed individual responses (retry the whole run for now)
- Cancel a running job mid-execution
- Parallel LLM calls within a single run
- WebSocket fallback (SSE, long polling)
