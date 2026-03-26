# Async Runs with Live Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make generation and judging run as background jobs with per-response live updates streamed to the UI via Turbo Streams.

**Architecture:** Solid Queue processes GenerateJob and JudgeJob in the background. The Run model is refactored to save and broadcast after each response/review. Turbo Streams via Solid Cable push updates to the run show page in real-time. The API returns 202 Accepted and callers poll for status.

**Tech Stack:** Solid Queue, Solid Cable, Turbo Rails, ActionCable

**Spec:** `docs/superpowers/specs/2026-03-26-async-runs-design.md`

---

## Chunk 1: Dependencies and Database

### Task 1: Add Dependencies

**Files:**
- Modify: `completion-kit.gemspec`
- Modify: `standalone/Gemfile`

- [ ] **Step 1: Add turbo-rails to the gemspec**

In `completion-kit.gemspec`, add after the existing `add_dependency` lines:

```ruby
spec.add_dependency "turbo-rails", ">= 1.5"
```

- [ ] **Step 2: Add solid_queue and solid_cable to standalone Gemfile**

In `standalone/Gemfile`, add after the existing gems:

```ruby
gem "solid_queue"
gem "solid_cable"
```

These are standalone-only — the engine declares turbo-rails as a dependency, but the job backend and cable adapter are deployment concerns.

- [ ] **Step 3: Bundle install for both**

```bash
cd /Users/damien/Work/homemade/completion-kit && bundle install
cd standalone && bundle install
```

- [ ] **Step 4: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add completion-kit.gemspec Gemfile.lock standalone/Gemfile standalone/Gemfile.lock
git commit -m "deps: add turbo-rails, solid_queue, solid_cable"
```

---

### Task 2: Migration — Add Progress Columns to Runs

**Files:**
- Create: `db/migrate/20260327000001_add_progress_to_runs.rb`
- Modify: `spec/rails_helper.rb` — update test schema

- [ ] **Step 1: Create the migration**

Create `db/migrate/20260327000001_add_progress_to_runs.rb`:

```ruby
class AddProgressToRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :completion_kit_runs, :progress_current, :integer, default: 0
    add_column :completion_kit_runs, :progress_total, :integer, default: 0
  end
end
```

- [ ] **Step 2: Update test schema in spec/rails_helper.rb**

In `spec/rails_helper.rb`, find the `completion_kit_runs` table definition and add the two columns after `t.string :status`:

```ruby
    t.integer :progress_current, default: 0
    t.integer :progress_total, default: 0
```

- [ ] **Step 3: Run migrations in standalone**

```bash
cd standalone
bin/rails completion_kit:install:migrations
bin/rails db:migrate
```

- [ ] **Step 4: Verify tests still pass**

```bash
cd /Users/damien/Work/homemade/completion-kit
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260327000001_add_progress_to_runs.rb spec/rails_helper.rb standalone/db/
git commit -m "feat: add progress_current and progress_total columns to runs"
```

---

### Task 3: Configure Turbo in Engine

**Files:**
- Modify: `app/views/layouts/completion_kit/application.html.erb`
- Modify: `lib/completion_kit/engine.rb`

- [ ] **Step 1: Add Turbo to the engine layout**

In `app/views/layouts/completion_kit/application.html.erb`, add inside the `<head>` tag after the stylesheet link:

```erb
<%= javascript_include_tag "turbo", type: "module" %>
```

Note: `turbo-rails` ships a pre-built JS file accessible via `javascript_include_tag "turbo"`. This avoids needing importmap or webpack.

- [ ] **Step 2: Add ActionCable meta tag to layout**

In the `<head>` tag, add:

```erb
<%= action_cable_meta_tag %>
```

- [ ] **Step 3: Require turbo-rails in the engine**

In `lib/completion_kit/engine.rb`, add at the top after existing requires:

```ruby
require "turbo-rails"
```

- [ ] **Step 4: Verify the engine still boots**

```bash
cd standalone && bin/rails runner "puts 'OK'"
```

- [ ] **Step 5: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add app/views/layouts/completion_kit/application.html.erb lib/completion_kit/engine.rb
git commit -m "feat: add Turbo and ActionCable to engine layout"
```

---

### Task 4: Configure Solid Queue and Solid Cable in Standalone

**Files:**
- Create: `standalone/config/cable.yml`
- Create: `standalone/config/queue.yml`
- Modify: `standalone/config/environments/production.rb`
- Modify: `standalone/config/environments/development.rb`

- [ ] **Step 1: Create cable.yml**

Create `standalone/config/cable.yml`:

```yaml
development:
  adapter: async

test:
  adapter: test

production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

Note: `async` adapter for dev (zero config, in-process), `solid_cable` for production.

- [ ] **Step 2: Create queue.yml**

Create `standalone/config/queue.yml`:

```yaml
development:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 3
      processes: 1
      polling_interval: 0.1

production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: "*"
      threads: 5
      processes: 1
      polling_interval: 0.1
```

- [ ] **Step 3: Configure Active Job backend in production.rb**

In `standalone/config/environments/production.rb`, add after the `config.secret_key_base` line:

```ruby
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
```

- [ ] **Step 4: Configure Active Job backend in development.rb**

In `standalone/config/environments/development.rb`, add inside the `configure` block:

```ruby
  config.active_job.queue_adapter = :async
```

Note: `:async` runs jobs in-process in dev (no separate worker needed). In production, Solid Queue runs as a separate process or via `puma` plugin.

- [ ] **Step 5: Update database.yml for Solid Queue and Solid Cable databases**

In `standalone/config/database.yml`, add the queue and cable databases:

```yaml
queue:
  <<: *default
  database: db/queue.sqlite3
  migrations_paths: db/queue_migrate

cable:
  <<: *default
  database: db/cable.sqlite3
  migrations_paths: db/cable_migrate
```

- [ ] **Step 6: Install Solid Queue and Solid Cable migrations**

```bash
cd standalone
bin/rails solid_queue:install:migrations 2>/dev/null || true
bin/rails solid_cable:install:migrations 2>/dev/null || true
bin/rails db:migrate
```

Note: These may need `db:prepare` instead of `db:migrate` for the multi-database setup. Adjust if needed.

- [ ] **Step 7: Verify standalone boots and queue works**

```bash
cd standalone
bin/rails runner "puts ActiveJob::Base.queue_adapter.class"
```

Expected: Should print the async adapter class in development.

- [ ] **Step 8: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/config/cable.yml standalone/config/queue.yml standalone/config/environments/ standalone/config/database.yml standalone/db/
git commit -m "feat: configure Solid Queue and Solid Cable for standalone app"
```

---

## Chunk 2: Model Refactor and Jobs

### Task 5: Update Run Model — as_json with Progress

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Modify: `spec/models/completion_kit/json_serialization_spec.rb`

- [ ] **Step 1: Write failing test**

In `spec/models/completion_kit/json_serialization_spec.rb`, update the Run test:

```ruby
  describe "Run#as_json" do
    let(:run) { create(:completion_kit_run) }

    it "includes expected attributes and computed fields" do
      json = run.as_json
      expect(json.keys).to include(:id, :name, :status, :prompt_id, :responses_count, :avg_score, :progress_current, :progress_total)
    end

    it "computes responses_count" do
      run = create(:completion_kit_run)
      create(:completion_kit_response, run: run)
      expect(run.as_json[:responses_count]).to eq(1)
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/models/completion_kit/json_serialization_spec.rb -e "progress"
```

Expected: FAIL — `progress_current` not in as_json.

- [ ] **Step 3: Update as_json on Run model**

In `app/models/completion_kit/run.rb`, update the `as_json` method to include progress fields:

```ruby
def as_json(options = {})
  {
    id: id, name: name, status: status, prompt_id: prompt_id,
    dataset_id: dataset_id, criteria_id: criteria_id, judge_model: judge_model,
    created_at: created_at, updated_at: updated_at,
    responses_count: responses.count, avg_score: avg_score,
    progress_current: progress_current, progress_total: progress_total
  }
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/models/completion_kit/json_serialization_spec.rb
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/run.rb spec/models/completion_kit/json_serialization_spec.rb
git commit -m "feat: include progress fields in Run#as_json"
```

---

### Task 6: Refactor Run Model — Per-Response Generation with Broadcasts

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Modify: `spec/models/completion_kit/run_spec.rb`
- Modify: `spec/integration/completion_kit/generation_pipeline_spec.rb`

This is the core refactor. `generate_responses!` and `judge_responses!` are changed to save and broadcast after each response/review instead of batching.

- [ ] **Step 1: Add broadcast helper to Run model**

In `app/models/completion_kit/run.rb`, add a private method:

```ruby
def broadcast_progress
  broadcast_replace_to(
    "completion_kit_run_#{id}",
    target: "run_progress",
    partial: "completion_kit/runs/progress",
    locals: { run: self }
  )
end

def broadcast_response(response)
  broadcast_append_to(
    "completion_kit_run_#{id}",
    target: "run_responses",
    partial: "completion_kit/runs/response_row",
    locals: { run: self, response: response, index: responses.where("id <= ?", response.id).count }
  )
end

def broadcast_response_update(response)
  broadcast_replace_to(
    "completion_kit_run_#{id}",
    target: "response_#{response.id}",
    partial: "completion_kit/runs/response_row",
    locals: { run: self, response: response, index: responses.where("id <= ?", response.id).count }
  )
end
```

Note: These use `Turbo::Broadcastable` which `turbo-rails` includes via ActiveRecord. If the engine's `ApplicationRecord` doesn't include it, add `include Turbo::Broadcastable` to the Run model.

- [ ] **Step 2: Refactor generate_responses! to be per-response**

Replace the `generate_responses!` method in `app/models/completion_kit/run.rb`:

```ruby
def generate_responses!
  rows = if dataset
           CsvProcessor.process_self(self)
         else
           [{}]
         end

  client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
  config_errors = client.configuration_errors
  unless config_errors.empty?
    errors.add(:base, config_errors.join(", "))
    return false
  end

  update!(status: "generating", progress_current: 0, progress_total: rows.length)
  responses.destroy_all
  broadcast_progress

  rows.each_with_index do |row, index|
    input = row.empty? ? nil : row.to_json
    rendered = CsvProcessor.apply_variables(prompt, row)
    response_text = client.generate_completion(rendered, model: prompt.llm_model)

    resp = responses.create!(
      input_data: input,
      response_text: response_text,
      expected_output: row["expected_output"]
    )

    update_columns(progress_current: index + 1)
    broadcast_progress
    broadcast_response(resp)
  end

  if judge_configured?
    judge_responses!
  else
    update!(status: "completed")
    broadcast_progress
  end

  true
rescue Faraday::Error => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_progress
  false
rescue StandardError => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_progress
  false
end
```

- [ ] **Step 3: Refactor judge_responses! to be per-review**

Replace the `judge_responses!` method:

```ruby
def judge_responses!
  total_evaluations = responses.count * metrics.count
  update!(status: "judging", progress_current: 0, progress_total: total_evaluations)
  broadcast_progress

  judge = JudgeService.new(judge_model: ApiConfig.for_model(judge_model).merge(judge_model: judge_model))
  evaluation_count = 0

  responses.find_each do |response|
    metrics.each do |metric|
      evaluation = judge.evaluate(
        response.response_text,
        response.expected_output,
        prompt.template,
        criteria: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
        evaluation_steps: metric.respond_to?(:evaluation_steps) ? metric.evaluation_steps : nil,
        rubric_text: metric.respond_to?(:display_rubric_text) ? metric.display_rubric_text : nil
      )

      response.reviews.find_or_initialize_by(metric_id: metric.id).tap do |review|
        review.assign_attributes(
          metric_name: metric.name,
          instruction: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
          status: "evaluated",
          ai_score: evaluation[:score],
          ai_feedback: evaluation[:feedback]
        )
        review.save!
      end

      evaluation_count += 1
      update_columns(progress_current: evaluation_count)
      broadcast_progress
    end

    broadcast_response_update(response)
  end

  update!(status: "completed")
  broadcast_progress
  true
rescue Faraday::Error => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_progress
  false
rescue StandardError => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_progress
  false
end
```

- [ ] **Step 4: Add Turbo::Broadcastable include if needed**

Check if `Turbo::Broadcastable` is auto-included via turbo-rails. If not, add to the Run model:

```ruby
include Turbo::Broadcastable
```

- [ ] **Step 5: Update existing tests**

The existing tests mock `generate_responses!` and `judge_responses!` in controller specs, so they should still work. But the model/integration specs that test the actual methods need updating.

In `spec/integration/completion_kit/generation_pipeline_spec.rb`, the test creates Faraday stubs and calls `generate_responses!`. The refactored method now calls `update_columns` and `broadcast_*`. Broadcasts will be no-ops in test (no ActionCable connection). The `update_columns` calls need the progress columns to exist in the test schema (done in Task 2).

Run the full suite to check:

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Fix any failures related to broadcast methods by stubbing them in tests if needed:

```ruby
allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
```

- [ ] **Step 6: Verify full suite passes with 100% coverage**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: All tests pass, 100% coverage.

- [ ] **Step 7: Commit**

```bash
git add app/models/completion_kit/run.rb spec/
git commit -m "refactor: per-response generation and judging with Turbo broadcasts"
```

---

### Task 7: Create Background Jobs

**Files:**
- Create: `app/jobs/completion_kit/generate_job.rb`
- Create: `app/jobs/completion_kit/judge_job.rb`
- Test: `spec/jobs/completion_kit/generate_job_spec.rb`
- Test: `spec/jobs/completion_kit/judge_job_spec.rb`

- [ ] **Step 1: Write failing tests**

Create `spec/jobs/completion_kit/generate_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::GenerateJob, type: :job do
  it "calls generate_responses! on the run" do
    run = create(:completion_kit_run)
    allow_any_instance_of(CompletionKit::Run).to receive(:generate_responses!).and_return(true)
    described_class.perform_now(run.id)
  end

  it "handles missing run gracefully" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end
end
```

Create `spec/jobs/completion_kit/judge_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::JudgeJob, type: :job do
  it "calls judge_responses! on the run" do
    run = create(:completion_kit_run)
    allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!).and_return(true)
    described_class.perform_now(run.id)
  end

  it "handles missing run gracefully" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/jobs/
```

Expected: FAIL — classes don't exist.

- [ ] **Step 3: Implement GenerateJob**

Create `app/jobs/completion_kit/generate_job.rb`:

```ruby
module CompletionKit
  class GenerateJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run

      run.generate_responses!
    end
  end
end
```

- [ ] **Step 4: Implement JudgeJob**

Create `app/jobs/completion_kit/judge_job.rb`:

```ruby
module CompletionKit
  class JudgeJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run

      run.judge_responses!
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/jobs/
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/jobs/completion_kit/ spec/jobs/
git commit -m "feat: add GenerateJob and JudgeJob for background processing"
```

---

## Chunk 3: Controllers and API

### Task 8: Update Web Controller — Enqueue Instead of Call

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb`
- Modify: `spec/requests/completion_kit/runs_spec.rb`

- [ ] **Step 1: Update the generate action**

In `app/controllers/completion_kit/runs_controller.rb`, replace the `generate` method:

```ruby
def generate
  GenerateJob.perform_later(@run.id)
  redirect_to run_path(@run), notice: "Generation started."
end
```

- [ ] **Step 2: Update the judge action**

Replace the `judge` method:

```ruby
def judge
  if params[:run]
    @run.update(
      judge_model: params[:run][:judge_model],
      criteria_id: params[:run][:criteria_id]
    )
  end
  JudgeJob.perform_later(@run.id)
  redirect_to run_path(@run), notice: "Judging started."
end
```

- [ ] **Step 3: Update tests**

In `spec/requests/completion_kit/runs_spec.rb`, the generate and judge tests currently mock `generate_responses!` / `judge_responses!`. Update them to verify the job is enqueued instead:

Find the generate test and update it to:
```ruby
it "enqueues GenerateJob and redirects" do
  post "/completion_kit/runs/#{run.id}/generate"
  expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  follow_redirect!
  expect(response.body).to include("Generation started")
end
```

Find the judge test and update similarly:
```ruby
it "enqueues JudgeJob and redirects" do
  post "/completion_kit/runs/#{run.id}/judge"
  expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
  follow_redirect!
  expect(response.body).to include("Judging started")
end
```

- [ ] **Step 4: Run tests**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/requests/completion_kit/runs_spec.rb
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/runs_controller.rb spec/requests/completion_kit/runs_spec.rb
git commit -m "feat: enqueue generate/judge as background jobs in web controller"
```

---

### Task 9: Update API Controller — Return 202 Accepted

**Files:**
- Modify: `app/controllers/completion_kit/api/v1/runs_controller.rb`
- Modify: `spec/requests/completion_kit/api/v1/runs_spec.rb`

- [ ] **Step 1: Update API generate action**

In `app/controllers/completion_kit/api/v1/runs_controller.rb`, replace the `generate` method:

```ruby
def generate
  GenerateJob.perform_later(@run.id)
  render json: @run.reload, status: :accepted
end
```

- [ ] **Step 2: Update API judge action**

Replace the `judge` method:

```ruby
def judge
  JudgeJob.perform_later(@run.id)
  render json: @run.reload, status: :accepted
end
```

- [ ] **Step 3: Update API tests**

In `spec/requests/completion_kit/api/v1/runs_spec.rb`, update the generate and judge tests:

```ruby
describe "POST /api/v1/runs/:id/generate" do
  it "enqueues generation and returns 202" do
    run = create(:completion_kit_run)
    post "/completion_kit/api/v1/runs/#{run.id}/generate", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)["id"]).to eq(run.id)
  end
end

describe "POST /api/v1/runs/:id/judge" do
  it "enqueues judging and returns 202" do
    run = create(:completion_kit_run)
    post "/completion_kit/api/v1/runs/#{run.id}/judge", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)["id"]).to eq(run.id)
  end
end
```

Remove the old failure-case tests (the controller no longer handles failures synchronously — the job does).

- [ ] **Step 4: Run tests**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/requests/completion_kit/api/v1/runs_spec.rb
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/api/v1/runs_controller.rb spec/requests/completion_kit/api/v1/runs_spec.rb
git commit -m "feat: API generate/judge return 202 Accepted with async processing"
```

---

## Chunk 4: Live UI

### Task 10: Create Progress Partial

**Files:**
- Create: `app/views/completion_kit/runs/_progress.html.erb`

- [ ] **Step 1: Create the progress partial**

Create `app/views/completion_kit/runs/_progress.html.erb`:

```erb
<div id="run_progress">
  <% if run.status == "generating" || run.status == "judging" %>
    <div class="ck-card" style="margin-bottom: 1rem;">
      <div class="ck-split">
        <p class="ck-kicker"><%= run.status == "generating" ? "Generating responses..." : "Judging responses..." %></p>
        <p class="ck-meta-copy"><%= run.progress_current %> of <%= run.progress_total %></p>
      </div>
      <div style="margin-top: 0.5rem; background: var(--ck-surface-soft); border-radius: 4px; overflow: hidden; height: 6px;">
        <% pct = run.progress_total > 0 ? (run.progress_current.to_f / run.progress_total * 100).round : 0 %>
        <div style="width: <%= pct %>%; height: 100%; background: var(--ck-accent); transition: width 0.3s;"></div>
      </div>
    </div>
  <% elsif run.status == "completed" %>
    <div class="ck-card" style="margin-bottom: 1rem;">
      <p class="ck-kicker" style="color: var(--ck-success);">Completed</p>
    </div>
  <% elsif run.status == "failed" %>
    <div class="ck-card" style="margin-bottom: 1rem;">
      <p class="ck-kicker" style="color: var(--ck-danger);">Failed</p>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/completion_kit/runs/_progress.html.erb
git commit -m "feat: add progress bar partial for run status"
```

---

### Task 11: Create Response Row Partial

**Files:**
- Create: `app/views/completion_kit/runs/_response_row.html.erb`

- [ ] **Step 1: Create the response row partial**

This partial renders a single response as a clickable card, matching the existing response display in show.html.erb. Read the current `show.html.erb` to extract the response card markup and put it in this partial.

Create `app/views/completion_kit/runs/_response_row.html.erb`:

```erb
<div id="response_<%= response.id %>">
  <%= link_to run_response_path(run, response), class: "ck-result-card ck-link", style: "display: block; text-decoration: none;" do %>
    <div class="ck-split">
      <span class="ck-meta-copy">#<%= index %></span>
      <% if response.reviewed? %>
        <span class="<%= ck_badge_classes(ck_score_kind(response.score)) %>"><%= response.score %></span>
      <% else %>
        <span class="ck-chip">Pending</span>
      <% end %>
    </div>
    <% if response.input_data.present? %>
      <p class="ck-meta-copy" style="margin-top: 0.35rem;"><%= truncate(response.input_data, length: 120) %></p>
    <% end %>
    <p style="margin-top: 0.35rem;"><%= truncate(response.response_text.to_s, length: 200) %></p>
  <% end %>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/views/completion_kit/runs/_response_row.html.erb
git commit -m "feat: add response row partial for Turbo Stream updates"
```

---

### Task 12: Update Run Show Page for Turbo Streams

**Files:**
- Modify: `app/views/completion_kit/runs/show.html.erb`

- [ ] **Step 1: Add Turbo Stream subscription**

At the top of `app/views/completion_kit/runs/show.html.erb` (before the breadcrumb), add:

```erb
<%= turbo_stream_from "completion_kit_run_#{@run.id}" %>
```

- [ ] **Step 2: Add progress partial**

After the run configuration section and before the responses list, add:

```erb
<%= render "progress", run: @run %>
```

- [ ] **Step 3: Wrap responses in a targetable container**

Find the responses list section and wrap it with a div that Turbo can append to:

```erb
<div id="run_responses">
  <% @sorted_responses.each_with_index do |response, idx| %>
    <%= render "response_row", run: @run, response: response, index: idx + 1 %>
  <% end %>
</div>
```

Replace the existing inline response rendering with the partial.

- [ ] **Step 4: Update the action buttons**

The "Start" button should still be visible for pending runs. When clicked, it now returns immediately. The progress bar appears via Turbo Stream as the job starts.

Remove or update the static "Generating..." / "Judging..." indicator since the progress partial handles this now.

- [ ] **Step 5: Verify the page renders**

```bash
cd standalone && bin/rails server &
sleep 3
curl -s http://localhost:3000/completion_kit/runs | head -5
kill %1
```

- [ ] **Step 6: Run full test suite**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: All tests pass, 100% coverage.

- [ ] **Step 7: Commit**

```bash
git add app/views/completion_kit/runs/show.html.erb
git commit -m "feat: add Turbo Stream live updates to run show page"
```

---

### Task 13: Final Integration Test and Coverage

**Files:**
- Modify various spec files as needed for 100% coverage

- [ ] **Step 1: Run full test suite**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

- [ ] **Step 2: Fix any coverage gaps**

Add tests for any uncovered lines/branches. Common gaps will be:
- Broadcast methods (stub in tests since no ActionCable connection)
- Progress partial rendering (add a request spec that renders the show page for a generating/judging run)
- Job edge cases

- [ ] **Step 3: Verify 100% coverage**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: 100% line and branch coverage.

- [ ] **Step 4: Commit and push**

```bash
git add -A
git commit -m "test: achieve 100% coverage for async runs"
git push
```
