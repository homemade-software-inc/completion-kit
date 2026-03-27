# Direct Metrics on Runs

**Goal:** Allow selecting individual metrics on a run instead of requiring a criteria group. Criteria becomes a UI shortcut for selecting multiple metrics at once, not a stored relationship on the run.

---

## Database

### New Table

`completion_kit_run_metrics` join table:
- `run_id` (references, not null)
- `metric_id` (references, not null)
- `position` (integer)
- timestamps

### Column Removal

Drop `criteria_id` from `completion_kit_runs`.

---

## Run Model

Remove `belongs_to :criteria`. Add:

```ruby
has_many :run_metrics, dependent: :destroy
has_many :metrics, through: :run_metrics
```

The `metrics` method returns directly associated metrics ordered by position. No more fallback to criteria.

Update `judge_configured?` — judging requires `judge_model.present?` AND `metrics.any?`.

---

## Run Form

Remove the criteria dropdown. Replace with:

- Checkboxes for all available metrics
- A "criteria" quick-add dropdown above the checkboxes — selecting a criteria checks all its metrics. This is purely client-side JS, nothing is saved about the criteria on the run.
- The hint updates: "Select a judge model and at least one metric to enable judging."

---

## API

- Run strong params: replace `criteria_id` with `metric_ids: []`
- `Run#as_json`: replace `criteria_id` with `metric_ids`
- Run create/update: accept `metric_ids` array, replace all run_metrics associations (same pattern as criteria controller's `replace_metric_memberships`)

---

## RunMetric Model

```ruby
module CompletionKit
  class RunMetric < ApplicationRecord
    belongs_to :run
    belongs_to :metric
  end
end
```

---

## Files to Create

```
app/models/completion_kit/run_metric.rb
db/migrate/TIMESTAMP_add_direct_metrics_to_runs.rb
```

## Files to Modify

```
app/models/completion_kit/run.rb — remove criteria, add run_metrics/metrics associations
app/controllers/completion_kit/runs_controller.rb — update params, handle metric_ids
app/controllers/completion_kit/api/v1/runs_controller.rb — update params, handle metric_ids
app/views/completion_kit/runs/_form.html.erb — replace criteria dropdown with metric checkboxes + criteria quick-add
app/views/completion_kit/runs/show.html.erb — update metrics display (no more criteria reference)
spec/rails_helper.rb — add run_metrics table to test schema, remove criteria_id from runs
```

## What Stays

- The Criteria model and UI — unchanged, still useful for grouping metrics
- Criteria controller and API — unchanged
- CriteriaMembership — unchanged

## Out of Scope

- Removing the Criteria model/feature entirely
- Ordering metrics within a run (position is set by selection order)
