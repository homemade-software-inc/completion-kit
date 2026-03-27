# Direct Metrics on Runs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the criteria_id foreign key on runs with a direct many-to-many metrics association, making criteria a UI shortcut instead of a stored relationship.

**Architecture:** Add a `run_metrics` join table. Remove `criteria_id` from runs. Update the run form with metric checkboxes and a criteria quick-add dropdown (client-side only). Update the API to accept `metric_ids` instead of `criteria_id`.

**Tech Stack:** Rails, RSpec, FactoryBot

**Spec:** `docs/superpowers/specs/2026-03-27-direct-metrics-on-runs-design.md`

---

## Chunk 1: Database and Model

### Task 1: Migration — Add RunMetrics Join Table, Remove criteria_id

**Files:**
- Create: `db/migrate/20260327100001_replace_criteria_with_direct_metrics_on_runs.rb`
- Modify: `spec/rails_helper.rb` — update test schema

- [ ] **Step 1: Create the migration**

Create `db/migrate/20260327100001_replace_criteria_with_direct_metrics_on_runs.rb`:

```ruby
class ReplaceCriteriaWithDirectMetricsOnRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :completion_kit_run_metrics do |t|
      t.references :run, null: false, foreign_key: { to_table: :completion_kit_runs }
      t.references :metric, null: false, foreign_key: { to_table: :completion_kit_metrics }
      t.integer :position
      t.timestamps
    end

    remove_reference :completion_kit_runs, :criteria, foreign_key: { to_table: :completion_kit_criteria }
  end
end
```

- [ ] **Step 2: Update test schema in spec/rails_helper.rb**

Add the `run_metrics` table after the `completion_kit_runs` table:

```ruby
  create_table :completion_kit_run_metrics, force: true do |t|
    t.references :run, null: false
    t.references :metric, null: false
    t.integer :position
    t.timestamps
  end
```

Remove `t.references :criteria` from the `completion_kit_runs` table definition.

- [ ] **Step 3: Run migrations in standalone**

```bash
cd standalone
bin/rails completion_kit:install:migrations
bin/rails db:migrate
```

- [ ] **Step 4: Commit**

```bash
git add db/migrate/ spec/rails_helper.rb standalone/db/
git commit -m "feat: add run_metrics join table, remove criteria_id from runs"
```

---

### Task 2: RunMetric Model

**Files:**
- Create: `app/models/completion_kit/run_metric.rb`

- [ ] **Step 1: Create the model**

Create `app/models/completion_kit/run_metric.rb`:

```ruby
module CompletionKit
  class RunMetric < ApplicationRecord
    belongs_to :run
    belongs_to :metric
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/models/completion_kit/run_metric.rb
git commit -m "feat: add RunMetric join model"
```

---

### Task 3: Update Run Model — Replace criteria with direct metrics

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Modify: `spec/models/completion_kit/run_spec.rb`
- Create: `spec/factories/run_metrics.rb`

- [ ] **Step 1: Update the Run model**

In `app/models/completion_kit/run.rb`:

Remove:
```ruby
belongs_to :criteria, optional: true, class_name: "CompletionKit::Criteria", foreign_key: "criteria_id"
```

Add:
```ruby
has_many :run_metrics, dependent: :destroy
has_many :metrics, through: :run_metrics
```

Replace the `metrics` method:
```ruby
def metrics
  run_metrics.order(:position).map(&:metric)
end
```

Note: This overrides the `has_many :metrics, through:` — we need the ordered version. Actually, remove the explicit `def metrics` method and use the association with a scope instead:

```ruby
has_many :run_metrics, -> { order(:position) }, dependent: :destroy
has_many :metrics, through: :run_metrics
```

This way `run.metrics` returns ordered metrics via the association.

Update `judge_configured?`:
```ruby
def judge_configured?
  judge_model.present? && metrics.any? && ApiConfig.valid_for_model?(judge_model)
end
```

Update `as_json` — replace `criteria_id` with `metric_ids`:
```ruby
def as_json(options = {})
  {
    id: id, name: name, status: status, prompt_id: prompt_id,
    dataset_id: dataset_id, judge_model: judge_model,
    created_at: created_at, updated_at: updated_at,
    responses_count: responses.count, avg_score: avg_score,
    progress_current: progress_current, progress_total: progress_total,
    metric_ids: metric_ids
  }
end
```

- [ ] **Step 2: Create run_metrics factory**

Create `spec/factories/run_metrics.rb`:

```ruby
FactoryBot.define do
  factory :completion_kit_run_metric, class: "CompletionKit::RunMetric" do
    association :run, factory: :completion_kit_run
    association :metric, factory: :completion_kit_metric
    sequence(:position) { |n| n }
  end
end
```

- [ ] **Step 3: Update run model specs**

In `spec/models/completion_kit/run_spec.rb`, find the `metrics` test at the top:

Replace:
```ruby
it "returns empty array when criteria is nil" do
  run = build(:completion_kit_run, criteria: nil)
  expect(run.metrics).to eq([])
end
```

With:
```ruby
it "returns empty array when no metrics associated" do
  run = create(:completion_kit_run)
  expect(run.metrics).to eq([])
end

it "returns associated metrics ordered by position" do
  run = create(:completion_kit_run)
  m1 = create(:completion_kit_metric, name: "Second")
  m2 = create(:completion_kit_metric, name: "First")
  CompletionKit::RunMetric.create!(run: run, metric: m1, position: 2)
  CompletionKit::RunMetric.create!(run: run, metric: m2, position: 1)
  expect(run.metrics.map(&:name)).to eq(["First", "Second"])
end
```

Update the `judge_responses!` tests — replace criteria setup with direct metric association:

Find:
```ruby
let(:criteria) do
  c = create(:completion_kit_criteria)
  CompletionKit::CriteriaMembership.create!(criteria: c, metric: metric, position: 1)
  c
end
```

Replace with:
```ruby
before do
  CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
end
```

And update any `criteria: criteria` in run creation to remove it. The run just needs `judge_model: "gpt-4.1"` — metrics come from the join table now.

- [ ] **Step 4: Update integration specs**

In `spec/integration/completion_kit/judging_pipeline_spec.rb`:

Replace the criteria setup:
```ruby
let(:criteria) do
  c = create(:completion_kit_criteria, name: "QA Criteria")
  CompletionKit::CriteriaMembership.create!(criteria: c, metric: metric, position: 1)
  c
end
```

With direct metric association. And update the run creation to remove `criteria: criteria`, adding a `before` block:
```ruby
before do
  CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
end
```

- [ ] **Step 5: Update JSON serialization spec**

In `spec/models/completion_kit/json_serialization_spec.rb`, update the Run test to check for `metric_ids` instead of `criteria_id`:

```ruby
expect(json.keys).to include(:id, :name, :status, :prompt_id, :responses_count, :avg_score, :progress_current, :progress_total, :metric_ids)
```

- [ ] **Step 6: Run full test suite**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: All pass, 100% coverage.

- [ ] **Step 7: Commit**

```bash
git add app/models/completion_kit/run.rb app/models/completion_kit/run_metric.rb spec/
git commit -m "feat: replace criteria_id with direct metric associations on runs"
```

---

## Chunk 2: Controllers and API

### Task 4: Update Web Controller

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb`
- Modify: `spec/requests/completion_kit/runs_spec.rb`

- [ ] **Step 1: Update run_params**

In `app/controllers/completion_kit/runs_controller.rb`, replace:
```ruby
params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, :criteria_id)
```

With:
```ruby
params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, metric_ids: [])
```

- [ ] **Step 2: Update create and update actions to handle metric_ids**

In the `create` action, after `@run.save`, add metric association:
```ruby
def create
  @run = Run.new(run_params.except(:metric_ids))
  if @run.save
    replace_run_metrics(@run, params[:run][:metric_ids])
    redirect_to run_path(@run), notice: "Run was successfully created."
  else
    load_form_collections
    render :new, status: :unprocessable_entity
  end
end
```

In the `update` action, add metric association after save:
```ruby
def update
  if @run.update(run_params.except(:metric_ids))
    replace_run_metrics(@run, params[:run][:metric_ids]) if params[:run]&.key?(:metric_ids)
    redirect_to run_path(@run), notice: "Run was successfully updated."
  else
    load_form_collections
    render :edit, status: :unprocessable_entity
  end
end
```

Add a private method:
```ruby
def replace_run_metrics(run, metric_ids)
  return unless metric_ids
  run.run_metrics.delete_all
  Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
    run.run_metrics.create!(metric_id: metric_id, position: index + 1)
  end
end
```

- [ ] **Step 3: Update load_form_collections**

Replace:
```ruby
@criterias = Criteria.includes(:metrics).order(:name)
```

With:
```ruby
@criterias = Criteria.includes(:metrics).order(:name)
@all_metrics = Metric.order(:name)
```

Keep `@criterias` — it's still needed for the quick-add dropdown.

- [ ] **Step 4: Update the judge action**

Remove `criteria_id` from the judge action params update. It currently does:
```ruby
@run.update(
  judge_model: params[:run][:judge_model],
  criteria_id: params[:run][:criteria_id]
)
```

Replace with:
```ruby
@run.update(judge_model: params[:run][:judge_model]) if params[:run]
```

- [ ] **Step 5: Update request specs**

In `spec/requests/completion_kit/runs_spec.rb`, update any test that references `criteria_id` in params. The judge action test that updates `criteria_id` should be updated to just update `judge_model`.

- [ ] **Step 6: Run tests**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/requests/completion_kit/runs_spec.rb
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add app/controllers/completion_kit/runs_controller.rb spec/requests/completion_kit/runs_spec.rb
git commit -m "feat: update web controller to use metric_ids instead of criteria_id"
```

---

### Task 5: Update API Controller

**Files:**
- Modify: `app/controllers/completion_kit/api/v1/runs_controller.rb`
- Modify: `spec/requests/completion_kit/api/v1/runs_spec.rb`

- [ ] **Step 1: Update API run_params**

Replace:
```ruby
params.permit(:name, :prompt_id, :dataset_id, :judge_model, :criteria_id)
```

With:
```ruby
params.permit(:name, :prompt_id, :dataset_id, :judge_model, metric_ids: [])
```

- [ ] **Step 2: Update create and update to handle metric_ids**

In the `create` action:
```ruby
def create
  run = Run.new(run_params.except(:metric_ids))
  if run.save
    replace_run_metrics(run, params[:metric_ids])
    render json: run.reload, status: :created
  else
    render json: {errors: run.errors}, status: :unprocessable_entity
  end
end
```

In the `update` action:
```ruby
def update
  if @run.update(run_params.except(:metric_ids))
    replace_run_metrics(@run, params[:metric_ids]) if params.key?(:metric_ids)
    render json: @run.reload
  else
    render json: {errors: @run.errors}, status: :unprocessable_entity
  end
end
```

Add private method:
```ruby
def replace_run_metrics(run, metric_ids)
  return unless metric_ids
  run.run_metrics.delete_all
  Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
    run.run_metrics.create!(metric_id: metric_id, position: index + 1)
  end
end
```

- [ ] **Step 3: Update API tests**

In `spec/requests/completion_kit/api/v1/runs_spec.rb`, add a test for creating a run with metric_ids:

```ruby
it "creates a run with metric_ids" do
  prompt = create(:completion_kit_prompt)
  metric = create(:completion_kit_metric)
  post "/completion_kit/api/v1/runs",
    params: {prompt_id: prompt.id, metric_ids: [metric.id]}.to_json,
    headers: headers
  expect(response).to have_http_status(:created)
  body = JSON.parse(response.body)
  expect(body["metric_ids"]).to eq([metric.id])
end
```

- [ ] **Step 4: Run tests**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec spec/requests/completion_kit/api/v1/runs_spec.rb
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/api/v1/runs_controller.rb spec/requests/completion_kit/api/v1/runs_spec.rb
git commit -m "feat: API accepts metric_ids instead of criteria_id for runs"
```

---

## Chunk 3: UI

### Task 6: Update Run Form — Metric Checkboxes with Criteria Quick-Add

**Files:**
- Modify: `app/views/completion_kit/runs/_form.html.erb`

- [ ] **Step 1: Replace criteria dropdown with metric checkboxes and criteria quick-add**

Remove the criteria field (lines 44-46 in the current form) and replace with:

```erb
<div class="ck-field">
  <label class="ck-label">Metrics</label>
  <% if @all_metrics.empty? %>
    <p class="ck-meta-copy">No metrics yet. <%= link_to "Create a metric", new_metric_path, class: "ck-link" %> first.</p>
  <% else %>
    <% if @criterias.any? %>
      <p class="ck-meta-copy" style="margin-bottom: 0.5rem;">
        Quick add:&ensp;
        <% @criterias.each do |c| %>
          <span class="ck-chip" style="cursor: pointer;" onclick="ckQuickAddCriteria(<%= c.metric_ids.to_json %>)"><%= c.name %></span>&ensp;
        <% end %>
      </p>
    <% end %>
    <div class="ck-metric-checkboxes">
      <% @all_metrics.each do |metric| %>
        <label class="ck-checkbox-label">
          <%= check_box_tag "run[metric_ids][]", metric.id, run.metric_ids.include?(metric.id), class: "ck-checkbox", id: "run_metric_#{metric.id}" %>
          <span><%= metric.name %></span>
        </label>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Update the JavaScript hint logic**

Replace the existing JavaScript that checks for `run_criteria` with logic that checks for any checked metrics:

```javascript
function updateJudgeHint() {
  var judge = document.getElementById('run_judge_model').value;
  var metrics = document.querySelectorAll('input[name="run[metric_ids][]"]:checked');
  var hint = document.getElementById('run-judge-hint');
  if (judge && metrics.length > 0) {
    hint.textContent = 'Responses will be generated then judged automatically.';
    hint.className = 'ck-form-hint ck-form-hint--success';
    hint.style.display = '';
  } else if (judge && metrics.length === 0) {
    hint.textContent = 'Select at least one metric to enable judging.';
    hint.className = 'ck-form-hint ck-form-hint--warn';
    hint.style.display = '';
  } else if (!judge && metrics.length > 0) {
    hint.textContent = 'Select a judge model to enable judging.';
    hint.className = 'ck-form-hint ck-form-hint--warn';
    hint.style.display = '';
  } else {
    hint.textContent = '';
    hint.style.display = 'none';
  }
}

function ckQuickAddCriteria(metricIds) {
  metricIds.forEach(function(id) {
    var cb = document.getElementById('run_metric_' + id);
    if (cb) cb.checked = true;
  });
  updateJudgeHint();
}

document.getElementById('run_judge_model').addEventListener('change', updateJudgeHint);
document.querySelectorAll('input[name="run[metric_ids][]"]').forEach(function(cb) {
  cb.addEventListener('change', updateJudgeHint);
});
updateJudgeHint();
```

- [ ] **Step 3: Commit**

```bash
git add app/views/completion_kit/runs/_form.html.erb
git commit -m "ui: replace criteria dropdown with metric checkboxes and criteria quick-add"
```

---

### Task 7: Update Run Show Page

**Files:**
- Modify: `app/views/completion_kit/runs/show.html.erb`

- [ ] **Step 1: Replace criteria display with metrics display**

Find the criteria section in the show page (the card that shows `@run.criteria.name` with metric count) and replace it with a display of the directly associated metrics:

Replace the criteria card with:
```erb
<% if @run.metrics.any? %>
  <span><%= @run.metrics.map(&:name).join(", ") %></span>
<% else %>
  <span class="ck-run-config__none">None</span>
<% end %>
```

Update the conditional that checks `!@run.criteria` to check `@run.metrics.empty?` instead.

- [ ] **Step 2: Run full test suite**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

Expected: All pass, 100% coverage.

- [ ] **Step 3: Commit**

```bash
git add app/views/completion_kit/runs/show.html.erb
git commit -m "ui: show direct metrics on run show page"
```

---

### Task 8: Add CSS for Metric Checkboxes

**Files:**
- Modify: `app/assets/stylesheets/completion_kit/application.css`

- [ ] **Step 1: Add checkbox styles**

Add to the CSS:

```css
.ck-metric-checkboxes {
  display: grid;
  gap: 0.35rem;
}

.ck-checkbox-label {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-family: var(--ck-sans);
  font-size: 0.9rem;
  color: var(--ck-text);
  cursor: pointer;
  padding: 0.35rem 0;
}

.ck-checkbox-label:hover {
  color: var(--ck-accent);
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/completion_kit/application.css
git commit -m "ui: add metric checkbox styles"
```

---

### Task 9: Final Coverage and Push

**Files:**
- Various spec files as needed

- [ ] **Step 1: Run full test suite**

```bash
BUNDLE_GEMFILE=/Users/damien/Work/homemade/completion-kit/Gemfile bundle exec rspec
```

- [ ] **Step 2: Fix any coverage gaps**

Common gaps will be:
- `replace_run_metrics` in both controllers
- `RunMetric` model (may need a basic test)
- New form branches

- [ ] **Step 3: Verify 100% coverage**

Expected: 100% line and branch coverage.

- [ ] **Step 4: Commit and push**

```bash
git add -A
git commit -m "test: achieve 100% coverage for direct metrics on runs"
git push
```
