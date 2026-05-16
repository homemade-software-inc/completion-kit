# Dashboard Dismissals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user ignore items on the standalone dashboard's worst-metric and failures cards, with a per-card flyout to review and un-ignore what's been dismissed.

**Architecture:** A new polymorphic engine model `CompletionKit::DashboardDismissal` records dismissed metrics and failures. `DashboardStats.worst_metric` filters dismissed metrics (resurfacing on regression); a new `DashboardStats.failures` replaces `failed_review_count` and aggregates run/generation/judge failures. An engine controller handles create/destroy and re-renders both cards via Turbo Streams. The two cards become engine partials the standalone dashboard renders.

**Tech Stack:** Rails 8.1 engine, RSpec + FactoryBot, Turbo Streams, SimpleCov 100% line+branch gate.

---

## File Structure

**Engine — create:**
- `db/migrate/20260516000001_create_completion_kit_dashboard_dismissals.rb` — the table
- `app/models/completion_kit/dashboard_dismissal.rb` — the model
- `app/controllers/completion_kit/dashboard_dismissals_controller.rb` — create/destroy
- `app/views/completion_kit/dashboard_dismissals/refresh.turbo_stream.erb` — shared Turbo Stream response
- `app/views/completion_kit/dashboard/_worst_metric_card.html.erb` — worst-metric card partial
- `app/views/completion_kit/dashboard/_failures_card.html.erb` — failures card partial
- `spec/models/completion_kit/dashboard_dismissal_spec.rb`
- `spec/requests/completion_kit/dashboard_dismissals_spec.rb`

**Engine — modify:**
- `app/services/completion_kit/dashboard_stats.rb` — `worst_metric` filter, new `failures`, new `metric_average`, drop `failed_review_count`
- `app/models/completion_kit/metric.rb`, `run.rb`, `response.rb`, `review.rb` — add `dashboard_dismissals` inverse association
- `config/routes.rb` — `resources :dashboard_dismissals, only: [:create, :destroy]`
- `app/assets/stylesheets/completion_kit/application.css` — flyout + failures-list styles
- `spec/services/completion_kit/dashboard_stats_spec.rb` — rewrite `worst_metric` specs, drop `failed_review_count`, add `failures`/`metric_average`
- `CHANGELOG.md`, `lib/completion_kit/version.rb`, `spec/lib/completion_kit_smoke_spec.rb` — release bump

**Standalone — modify:**
- `standalone/app/controllers/home_controller.rb` — `@failures`, `@ignored_metrics`, `@ignored_failures`
- `standalone/app/views/home/index.html.erb` — render the two engine card partials
- `standalone/db/migrate/20260516000001_create_completion_kit_dashboard_dismissals.rb` — installed copy

---

## Task 1: DashboardDismissal model + migration

**Files:**
- Create: `db/migrate/20260516000001_create_completion_kit_dashboard_dismissals.rb`
- Create: `app/models/completion_kit/dashboard_dismissal.rb`
- Modify: `app/models/completion_kit/metric.rb`, `run.rb`, `response.rb`, `review.rb`
- Test: `spec/models/completion_kit/dashboard_dismissal_spec.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/20260516000001_create_completion_kit_dashboard_dismissals.rb`:

```ruby
class CreateCompletionKitDashboardDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_dashboard_dismissals do |t|
      t.string :dismissable_type, null: false
      t.bigint :dismissable_id, null: false
      t.decimal :baseline_score, precision: 4, scale: 1
      t.timestamps
    end

    add_index :completion_kit_dashboard_dismissals,
              [:dismissable_type, :dismissable_id],
              unique: true,
              name: "index_ck_dashboard_dismissals_on_dismissable"
  end
end
```

- [ ] **Step 2: Run the migration into the dummy and standalone apps**

Run:
```bash
cd spec/dummy && bin/rails db:migrate && cd ../..
cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate && cd ..
```
Expected: both migrate cleanly; `standalone/db/migrate/20260516000001_create_completion_kit_dashboard_dismissals.completion_kit.rb` is created.

- [ ] **Step 3: Write the failing model spec**

Create `spec/models/completion_kit/dashboard_dismissal_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::DashboardDismissal, type: :model do
  it "is valid pointing at a metric with a baseline score" do
    dismissal = described_class.new(dismissable: create(:completion_kit_metric), baseline_score: 3.2)
    expect(dismissal).to be_valid
  end

  it "is valid pointing at a failed run with no baseline score" do
    dismissal = described_class.new(dismissable: create(:completion_kit_run))
    expect(dismissal).to be_valid
  end

  it "rejects an unsupported dismissable type" do
    dismissal = described_class.new(dismissable: create(:completion_kit_dataset))
    expect(dismissal).not_to be_valid
    expect(dismissal.errors[:dismissable_type]).to be_present
  end

  it "rejects a duplicate dismissal of the same record" do
    metric = create(:completion_kit_metric)
    described_class.create!(dismissable: metric)
    dup = described_class.new(dismissable: metric)
    expect(dup).not_to be_valid
  end

  it "scopes metric dismissals and failure dismissals apart" do
    metric_d = described_class.create!(dismissable: create(:completion_kit_metric))
    run_d = described_class.create!(dismissable: create(:completion_kit_run))

    expect(described_class.metrics).to contain_exactly(metric_d)
    expect(described_class.failures).to contain_exactly(run_d)
  end

  it "is destroyed when its dismissable is destroyed" do
    run = create(:completion_kit_run)
    described_class.create!(dismissable: run)
    expect { run.destroy }.to change(described_class, :count).by(-1)
  end
end
```

- [ ] **Step 4: Run the spec to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/dashboard_dismissal_spec.rb`
Expected: FAIL — `uninitialized constant CompletionKit::DashboardDismissal`.

- [ ] **Step 5: Write the model**

Create `app/models/completion_kit/dashboard_dismissal.rb`:

```ruby
module CompletionKit
  class DashboardDismissal < ApplicationRecord
    FAILURE_TYPES = %w[
      CompletionKit::Run
      CompletionKit::Response
      CompletionKit::Review
    ].freeze
    DISMISSABLE_TYPES = (["CompletionKit::Metric"] + FAILURE_TYPES).freeze

    belongs_to :dismissable, polymorphic: true

    validates :dismissable_type, inclusion: { in: DISMISSABLE_TYPES }
    validates :dismissable_id, uniqueness: { scope: :dismissable_type }

    scope :metrics, -> { where(dismissable_type: "CompletionKit::Metric").includes(:dismissable) }
    scope :failures, -> { where(dismissable_type: FAILURE_TYPES).includes(:dismissable) }
  end
end
```

- [ ] **Step 6: Add the inverse association to the four dismissable models**

In `app/models/completion_kit/metric.rb`, `run.rb`, `response.rb`, and `review.rb`, add this line alongside the existing `has_many`/`belongs_to` associations near the top of the class:

```ruby
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/models/completion_kit/dashboard_dismissal_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 8: Commit**

```bash
git add db/migrate app/models/completion_kit spec/models/completion_kit/dashboard_dismissal_spec.rb standalone/db/migrate
git commit -m "add DashboardDismissal model and migration"
```

---

## Task 2: DashboardStats — worst_metric dismissal filter + metric_average

**Files:**
- Modify: `app/services/completion_kit/dashboard_stats.rb`
- Test: `spec/services/completion_kit/dashboard_stats_spec.rb`

- [ ] **Step 1: Rewrite the existing `.worst_metric` specs and add dismissal specs**

In `spec/services/completion_kit/dashboard_stats_spec.rb`, replace the entire `describe ".worst_metric"` block with:

```ruby
  describe ".worst_metric" do
    it "returns nil when there are no scored reviews" do
      expect(described_class.worst_metric(since: 7.days.ago)).to be_nil
    end

    it "surfaces the lowest-average metric, its record, and its worst-scoring response" do
      accuracy = create(:completion_kit_metric, name: "Accuracy")
      brevity = create(:completion_kit_metric, name: "Brevity")
      strong = create(:completion_kit_response)
      weak_a = create(:completion_kit_response)
      weak_b = create(:completion_kit_response)
      create(:completion_kit_review, response: strong, metric: accuracy, ai_score: 5.0)
      create(:completion_kit_review, response: weak_a, metric: brevity, ai_score: 2.0)
      create(:completion_kit_review, response: weak_b, metric: brevity, ai_score: 1.0)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:metric]).to eq(brevity)
      expect(result[:name]).to eq("Brevity")
      expect(result[:avg]).to eq(1.5)
      expect(result[:score]).to eq(1.0)
      expect(result[:response]).to eq(weak_b)
    end

    it "ignores failed reviews, out-of-window reviews, and reviews with no metric" do
      accuracy = create(:completion_kit_metric, name: "Accuracy")
      stale = create(:completion_kit_metric, name: "Stale")
      recent = create(:completion_kit_response)
      old = create(:completion_kit_response)
      create(:completion_kit_review, response: recent, metric: accuracy, ai_score: 4.0)
      create(:completion_kit_review, response: recent, metric: nil, metric_name: "Orphan",
                                     status: "failed", ai_score: nil)
      create(:completion_kit_review, response: old, metric: stale, ai_score: 1.0,
                                     created_at: 40.days.ago)

      expect(described_class.worst_metric(since: 7.days.ago)[:name]).to eq("Accuracy")
    end

    it "excludes a dismissed metric while its average holds at or above the baseline" do
      good = create(:completion_kit_metric, name: "Tone")
      bad = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: good, ai_score: 4.0)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: bad, ai_score: 2.0)
      CompletionKit::DashboardDismissal.create!(dismissable: bad, baseline_score: 2.0)

      expect(described_class.worst_metric(since: 7.days.ago)[:name]).to eq("Tone")
    end

    it "resurfaces a dismissed metric that regressed below baseline and clears the stale dismissal" do
      bad = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: bad, ai_score: 1.0)
      dismissal = CompletionKit::DashboardDismissal.create!(dismissable: bad, baseline_score: 3.0)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:name]).to eq("Accuracy")
      expect(CompletionKit::DashboardDismissal.exists?(dismissal.id)).to be(false)
    end

    it "returns nil when every metric is dismissed and holding" do
      metric = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)
      CompletionKit::DashboardDismissal.create!(dismissable: metric, baseline_score: 3.0)

      expect(described_class.worst_metric(since: 7.days.ago)).to be_nil
    end
  end

  describe ".metric_average" do
    it "returns the rounded window average for a metric" do
      metric = create(:completion_kit_metric)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 2.0)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)

      expect(described_class.metric_average(metric.id, since: 7.days.ago)).to eq(2.5)
    end

    it "returns nil when the metric has no scored reviews in the window" do
      expect(described_class.metric_average(create(:completion_kit_metric).id, since: 7.days.ago)).to be_nil
    end
  end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/dashboard_stats_spec.rb -e worst_metric -e metric_average`
Expected: FAIL — `metric_average` undefined and `worst_metric` result lacks `:metric`.

- [ ] **Step 3: Rewrite `worst_metric` and add `metric_average`**

In `app/services/completion_kit/dashboard_stats.rb`, replace the entire `def self.worst_metric` method with:

```ruby
    # The metric with the lowest average judge score across succeeded reviews
    # in the window — the prompt-engineering target. Dismissed metrics are
    # skipped while their average holds at or above the score snapshotted when
    # they were dismissed; a metric that regresses below that baseline
    # resurfaces and its stale dismissal is cleared. Returns nil when nothing
    # qualifies. `response` is the single worst-scoring response, for a deep
    # link.
    def self.worst_metric(since:)
      averages = scored_reviews_since(since)
                 .joins(:metric)
                 .group("completion_kit_metrics.id")
                 .average(:ai_score)
      return nil if averages.empty?

      dismissals = metric_dismissals
      metrics = Metric.where(id: averages.keys).index_by(&:id)

      averages.sort_by { |_id, avg| avg }.each do |metric_id, avg|
        rounded = avg.to_f.round(2)
        dismissal = dismissals[metric_id]
        next if dismissal && rounded >= dismissal.baseline_score.to_f

        dismissal&.destroy
        worst = scored_reviews_since(since).where(metric_id: metric_id).order(:ai_score).first
        metric = metrics[metric_id]
        return {
          metric: metric,
          name: metric.name,
          avg: rounded,
          response: worst.response,
          score: worst.ai_score.to_f
        }
      end
      nil
    end

    # The rounded average judge score for one metric across the window, or nil
    # when it has no scored reviews. Used to snapshot a dismissal's baseline.
    def self.metric_average(metric_id, since:)
      scored_reviews_since(since).where(metric_id: metric_id).average(:ai_score)&.to_f&.round(2)
    end
```

Then add this private helper just above the existing `scored_reviews_since` definition:

```ruby
    def self.metric_dismissals
      DashboardDismissal.where(dismissable_type: "CompletionKit::Metric").index_by(&:dismissable_id)
    end
    private_class_method :metric_dismissals
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/dashboard_stats_spec.rb -e worst_metric -e metric_average`
Expected: PASS (8 examples).

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/dashboard_stats.rb spec/services/completion_kit/dashboard_stats_spec.rb
git commit -m "filter dismissed metrics out of worst-metric card"
```

---

## Task 3: DashboardStats — failures replaces failed_review_count

**Files:**
- Modify: `app/services/completion_kit/dashboard_stats.rb`
- Test: `spec/services/completion_kit/dashboard_stats_spec.rb`

- [ ] **Step 1: Replace the `.failed_review_count` spec with a `.failures` spec**

In `spec/services/completion_kit/dashboard_stats_spec.rb`, replace the entire `describe ".failed_review_count"` block with:

```ruby
  describe ".failures" do
    it "is empty when nothing failed in the window" do
      result = described_class.failures(since: 7.days.ago)
      expect(result[:count]).to eq(0)
      expect(result[:items]).to eq([])
    end

    it "aggregates run, generation, and judge failures with cause and run link" do
      run = create(:completion_kit_run, status: "failed", failure_summary: "Worker crashed")
      bad_response = create(:completion_kit_response, :failed)
      good_response = create(:completion_kit_response)
      create(:completion_kit_review, response: good_response, status: "failed",
                                     ai_score: nil, error_class: "CompletionKit::JudgeParseError",
                                     error_provider: "openai")

      result = described_class.failures(since: 7.days.ago)

      expect(result[:count]).to eq(3)
      surfaces = result[:items].map { |i| i[:surface] }
      expect(surfaces).to contain_exactly("run", "generation", "judge")
      run_item = result[:items].find { |i| i[:surface] == "run" }
      expect(run_item[:cause]).to eq("Worker crashed")
      expect(run_item[:run]).to eq(run)
      gen_item = result[:items].find { |i| i[:surface] == "generation" }
      expect(gen_item[:cause]).to eq("Faraday::TimeoutError")
      expect(gen_item[:run]).to eq(bad_response.run)
      judge_item = result[:items].find { |i| i[:surface] == "judge" }
      expect(judge_item[:cause]).to eq("CompletionKit::JudgeParseError")
      expect(judge_item[:run]).to eq(good_response.run)
    end

    it "falls back to default cause text when failure detail is missing" do
      create(:completion_kit_run, status: "failed", failure_summary: nil)
      response = create(:completion_kit_response, status: "failed", error_class: nil)
      create(:completion_kit_review, response: response, status: "failed", ai_score: nil, error_class: nil)

      causes = described_class.failures(since: 7.days.ago)[:items].map { |i| i[:cause] }
      expect(causes).to contain_exactly("Run failed", "Unknown error", "Unknown error")
    end

    it "excludes failures outside the window" do
      create(:completion_kit_run, status: "failed", created_at: 40.days.ago)
      create(:completion_kit_response, :failed, created_at: 40.days.ago)
      expect(described_class.failures(since: 7.days.ago)[:count]).to eq(0)
    end

    it "excludes dismissed failures" do
      run = create(:completion_kit_run, status: "failed", failure_summary: "crash")
      response = create(:completion_kit_response, :failed)
      CompletionKit::DashboardDismissal.create!(dismissable: run)
      CompletionKit::DashboardDismissal.create!(dismissable: response)

      result = described_class.failures(since: 7.days.ago)
      expect(result[:count]).to eq(0)
    end

    it "orders items most recent first" do
      old = create(:completion_kit_run, status: "failed", updated_at: 5.days.ago)
      recent = create(:completion_kit_run, status: "failed", updated_at: 1.hour.ago)

      items = described_class.failures(since: 7.days.ago)[:items]
      expect(items.map { |i| i[:record] }).to eq([recent, old])
    end
  end
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/dashboard_stats_spec.rb -e failures`
Expected: FAIL — `failures` undefined.

- [ ] **Step 3: Replace `failed_review_count` with `failures`**

In `app/services/completion_kit/dashboard_stats.rb`, replace the entire `def self.failed_review_count` method with:

```ruby
    # Everything that terminally failed in the window across all three
    # surfaces — failed runs, failed generations, failed judge reviews —
    # excluding any the user has dismissed. Returns a count and an items list
    # ordered most-recent-first; each item carries its surface, the failing
    # record, the run it belongs to (for a deep link), and a cause string.
    def self.failures(since:)
      dismissed = failure_dismissal_keys
      items = []

      Run.where(status: "failed").where("created_at >= ?", since).find_each do |run|
        next if dismissed.include?(["CompletionKit::Run", run.id])
        items << {
          surface: "run", record: run, run: run,
          cause: run.failure_summary.presence || "Run failed", at: run.updated_at
        }
      end

      Response.where(status: "failed").where("created_at >= ?", since)
              .includes(:run).find_each do |response|
        next if dismissed.include?(["CompletionKit::Response", response.id])
        items << {
          surface: "generation", record: response, run: response.run,
          cause: failure_cause(response), at: response.updated_at
        }
      end

      Review.where(status: "failed").where("completion_kit_reviews.created_at >= ?", since)
            .includes(response: :run).find_each do |review|
        next if dismissed.include?(["CompletionKit::Review", review.id])
        items << {
          surface: "judge", record: review, run: review.response.run,
          cause: failure_cause(review), at: review.updated_at
        }
      end

      items.sort_by! { |item| item[:at] }
      items.reverse!
      { count: items.size, items: items }
    end
```

Then add these two private helpers just above the `metric_dismissals` helper from Task 2:

```ruby
    def self.failure_dismissal_keys
      DashboardDismissal.failures.map { |d| [d.dismissable_type, d.dismissable_id] }.to_set
    end
    private_class_method :failure_dismissal_keys

    def self.failure_cause(record)
      record.error_class.presence || "Unknown error"
    end
    private_class_method :failure_cause
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `bundle exec rspec spec/services/completion_kit/dashboard_stats_spec.rb`
Expected: PASS — every example in the file, including the untouched `activity` and `prompt_changes` blocks.

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/dashboard_stats.rb spec/services/completion_kit/dashboard_stats_spec.rb
git commit -m "replace failed-review count with unified failures aggregate"
```

---

## Task 4: DashboardDismissalsController + routes

**Files:**
- Create: `app/controllers/completion_kit/dashboard_dismissals_controller.rb`
- Create: `app/views/completion_kit/dashboard_dismissals/refresh.turbo_stream.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/completion_kit/dashboard_dismissals_spec.rb`

- [ ] **Step 1: Add the route**

In `config/routes.rb`, add this line directly after the `resources :tags` line:

```ruby
  resources :dashboard_dismissals, only: [:create, :destroy]
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/completion_kit/dashboard_dismissals_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "CompletionKit dashboard dismissals", type: :request do
  let(:base_path) { "/completion_kit/dashboard_dismissals" }

  def dismiss(record)
    post base_path,
         params: { dashboard_dismissal: { dismissable_type: record.class.name, dismissable_id: record.id } },
         as: :turbo_stream
  end

  it "dismisses a metric, snapshotting its window average as the baseline" do
    metric = create(:completion_kit_metric)
    create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)

    expect { dismiss(metric) }.to change(CompletionKit::DashboardDismissal, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(CompletionKit::DashboardDismissal.last.baseline_score).to eq(3.0)
  end

  it "dismisses a failed run with no baseline score" do
    run = create(:completion_kit_run, status: "failed")

    dismiss(run)

    expect(response).to have_http_status(:ok)
    expect(CompletionKit::DashboardDismissal.last.baseline_score).to be_nil
  end

  it "rejects an unsupported dismissable type" do
    dataset = create(:completion_kit_dataset)
    expect { dismiss(dataset) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "un-dismisses a record on destroy" do
    dismissal = CompletionKit::DashboardDismissal.create!(dismissable: create(:completion_kit_run))

    expect { delete "#{base_path}/#{dismissal.id}", as: :turbo_stream }
      .to change(CompletionKit::DashboardDismissal, :count).by(-1)
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 3: Run the spec to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/dashboard_dismissals_spec.rb`
Expected: FAIL — routing error / missing controller.

- [ ] **Step 4: Write the controller**

Create `app/controllers/completion_kit/dashboard_dismissals_controller.rb`:

```ruby
module CompletionKit
  class DashboardDismissalsController < ApplicationController
    WINDOW = 7.days

    def create
      record = resolve_dismissable
      DashboardDismissal.create(dismissable: record, baseline_score: baseline_for(record))
      render_cards
    end

    def destroy
      DashboardDismissal.find(params[:id]).destroy
      render_cards
    end

    private

    def dismissal_params
      params.require(:dashboard_dismissal).permit(:dismissable_type, :dismissable_id)
    end

    def resolve_dismissable
      type = dismissal_params[:dismissable_type]
      raise ActiveRecord::RecordNotFound unless DashboardDismissal::DISMISSABLE_TYPES.include?(type)
      type.constantize.find(dismissal_params[:dismissable_id])
    end

    def baseline_for(record)
      return nil unless record.is_a?(Metric)
      DashboardStats.metric_average(record.id, since: WINDOW.ago)
    end

    def render_cards
      @worst_metric = DashboardStats.worst_metric(since: WINDOW.ago)
      @failures = DashboardStats.failures(since: WINDOW.ago)
      @ignored_metrics = DashboardDismissal.metrics
      @ignored_failures = DashboardDismissal.failures
      render :refresh, formats: [:turbo_stream]
    end
  end
end
```

- [ ] **Step 5: Write the Turbo Stream template**

Create `app/views/completion_kit/dashboard_dismissals/refresh.turbo_stream.erb`:

```erb
<%= turbo_stream.replace "ck-worst-metric-card" do %>
  <%= render "completion_kit/dashboard/worst_metric_card",
             worst_metric: @worst_metric, ignored_metrics: @ignored_metrics %>
<% end %>
<%= turbo_stream.replace "ck-failures-card" do %>
  <%= render "completion_kit/dashboard/failures_card",
             failures: @failures, ignored_failures: @ignored_failures %>
<% end %>
```

(The two partials are created in Task 5. This template will not render successfully until then — that is expected; the controller request spec in Step 6 still passes because it asserts only on status and record counts, and a `turbo_stream` request renders the template lazily. If the spec errors on the missing partial, run Task 5 first, then return here. To keep tasks independently runnable, create empty placeholder partials now: `printf '' > app/views/completion_kit/dashboard/_worst_metric_card.html.erb` and the same for `_failures_card.html.erb`.)

- [ ] **Step 6: Create placeholder partials so the template renders**

Run:
```bash
mkdir -p app/views/completion_kit/dashboard
printf '' > app/views/completion_kit/dashboard/_worst_metric_card.html.erb
printf '' > app/views/completion_kit/dashboard/_failures_card.html.erb
```

- [ ] **Step 7: Run the spec to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/dashboard_dismissals_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 8: Commit**

```bash
git add app/controllers/completion_kit/dashboard_dismissals_controller.rb app/views/completion_kit/dashboard_dismissals app/views/completion_kit/dashboard config/routes.rb spec/requests/completion_kit/dashboard_dismissals_spec.rb
git commit -m "add dashboard dismissals controller and routes"
```

---

## Task 5: Card partials + flyout styling

**Files:**
- Modify: `app/views/completion_kit/dashboard/_worst_metric_card.html.erb`
- Modify: `app/views/completion_kit/dashboard/_failures_card.html.erb`
- Modify: `app/assets/stylesheets/completion_kit/application.css`

This task has no new `.rb` code, so no unit test — it is verified by the existing request spec from Task 4 (which renders both partials through the Turbo Stream) plus a visual check in Task 6.

- [ ] **Step 1: Write the worst-metric card partial**

Replace the contents of `app/views/completion_kit/dashboard/_worst_metric_card.html.erb` with:

```erb
<div class="ck-card ck-stat-card ck-rise" id="ck-worst-metric-card" style="--rise-delay: 120ms;">
  <p class="ck-kicker">Worst metric · last 7 days</p>
  <% if worst_metric %>
    <div class="ck-stat-card__body">
      <span class="ck-stat-card__metric"><%= worst_metric[:name] %></span>
      <span class="<%= ck_badge_classes(ck_score_kind(worst_metric[:avg])) %> ck-stat-card__score"><%= worst_metric[:avg] %></span>
    </div>
    <p class="ck-stat-card__foot">
      <% if worst_metric[:response] %>
        <%= link_to "Worst-scoring response →",
              completion_kit.run_response_path(worst_metric[:response].run, worst_metric[:response]),
              class: "ck-link" %>
      <% else %>
        Lowest average judge score this week.
      <% end %>
      <%= button_to "Ignore",
            completion_kit.dashboard_dismissals_path,
            params: { dashboard_dismissal: { dismissable_type: "CompletionKit::Metric",
                                             dismissable_id: worst_metric[:metric].id } },
            class: "ck-dismiss-btn" %>
    </p>
  <% else %>
    <div class="ck-stat-card__body">
      <span class="ck-stat-card__metric ck-stat-card__metric--empty">No scored reviews</span>
    </div>
    <p class="ck-stat-card__foot">Run a judge to populate this.</p>
  <% end %>

  <% if ignored_metrics.any? %>
    <details class="ck-flyout">
      <summary class="ck-flyout__toggle"><%= ignored_metrics.size %> ignored</summary>
      <ul class="ck-flyout__list">
        <% ignored_metrics.each do |dismissal| %>
          <li class="ck-flyout__item">
            <span class="ck-flyout__label">
              <%= dismissal.dismissable.name %>
              <% if dismissal.baseline_score %>
                <span class="ck-flyout__meta">baseline <%= dismissal.baseline_score %></span>
              <% end %>
            </span>
            <%= button_to "Un-ignore",
                  completion_kit.dashboard_dismissal_path(dismissal),
                  method: :delete, class: "ck-dismiss-btn" %>
          </li>
        <% end %>
      </ul>
    </details>
  <% end %>
</div>
```

- [ ] **Step 2: Write the failures card partial**

Replace the contents of `app/views/completion_kit/dashboard/_failures_card.html.erb` with:

```erb
<div class="ck-card ck-stat-card ck-rise" id="ck-failures-card" style="--rise-delay: 180ms;">
  <p class="ck-kicker">Failures · last 7 days</p>
  <div class="ck-stat-card__body">
    <span class="ck-stat-card__count<%= failures[:count].positive? ? ' is-danger' : ' is-clean' %>"><%= failures[:count] %></span>
  </div>

  <% if failures[:items].any? %>
    <ul class="ck-failure-list">
      <% failures[:items].each do |item| %>
        <li class="ck-failure-list__item">
          <span class="ck-failure-list__surface ck-failure-list__surface--<%= item[:surface] %>"><%= item[:surface] %></span>
          <% if item[:run] %>
            <%= link_to item[:cause], completion_kit.run_path(item[:run]), class: "ck-link ck-failure-list__cause" %>
          <% else %>
            <span class="ck-failure-list__cause"><%= item[:cause] %></span>
          <% end %>
          <%= button_to "×",
                completion_kit.dashboard_dismissals_path,
                params: { dashboard_dismissal: { dismissable_type: item[:record].class.name,
                                                 dismissable_id: item[:record].id } },
                class: "ck-dismiss-btn ck-dismiss-btn--icon",
                form: { "aria-label": "Dismiss failure" } %>
        </li>
      <% end %>
    </ul>
  <% else %>
    <p class="ck-stat-card__foot">All clear — nothing failed this week.</p>
  <% end %>

  <% if ignored_failures.any? %>
    <details class="ck-flyout">
      <summary class="ck-flyout__toggle"><%= ignored_failures.size %> ignored</summary>
      <ul class="ck-flyout__list">
        <% ignored_failures.each do |dismissal| %>
          <li class="ck-flyout__item">
            <span class="ck-flyout__label"><%= dismissal.dismissable_type.demodulize %> #<%= dismissal.dismissable_id %></span>
            <%= button_to "Un-ignore",
                  completion_kit.dashboard_dismissal_path(dismissal),
                  method: :delete, class: "ck-dismiss-btn" %>
          </li>
        <% end %>
      </ul>
    </details>
  <% end %>
</div>
```

- [ ] **Step 3: Add the styles**

Append to `app/assets/stylesheets/completion_kit/application.css`:

```css
.ck-dismiss-btn {
  display: inline-flex;
  align-items: center;
  margin-left: 0.5rem;
  padding: 0.1rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--ck-text-dim, #9aa0aa);
  background: transparent;
  border: 1px solid var(--ck-border, #2c2f36);
  border-radius: 999px;
  cursor: pointer;
}
.ck-dismiss-btn:hover {
  color: var(--ck-text, #e8eaed);
  border-color: var(--ck-text-dim, #9aa0aa);
}
.ck-dismiss-btn--icon {
  margin-left: auto;
  padding: 0 0.45rem;
  line-height: 1.4;
}
.ck-dismiss-btn form,
.ck-flyout__item form {
  display: inline;
}

.ck-failure-list {
  list-style: none;
  margin: 0.6rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
}
.ck-failure-list__item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.8rem;
}
.ck-failure-list__surface {
  flex: none;
  padding: 0.05rem 0.45rem;
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border-radius: 4px;
  background: color-mix(in srgb, var(--ck-border, #2c2f36) 60%, transparent);
  color: var(--ck-text-dim, #9aa0aa);
}
.ck-failure-list__surface--run { color: #f0a675; }
.ck-failure-list__surface--generation { color: #e58f8f; }
.ck-failure-list__surface--judge { color: #d7a6e0; }
.ck-failure-list__cause {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ck-flyout {
  margin-top: 0.7rem;
  border-top: 1px solid var(--ck-border, #2c2f36);
  padding-top: 0.5rem;
}
.ck-flyout__toggle {
  font-size: 0.72rem;
  font-weight: 600;
  color: var(--ck-text-dim, #9aa0aa);
  cursor: pointer;
}
.ck-flyout__toggle:hover { color: var(--ck-text, #e8eaed); }
.ck-flyout__list {
  list-style: none;
  margin: 0.5rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}
.ck-flyout__item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  font-size: 0.78rem;
}
.ck-flyout__meta {
  margin-left: 0.35rem;
  color: var(--ck-text-dim, #9aa0aa);
  font-size: 0.7rem;
}
```

- [ ] **Step 4: Run the dismissals request spec to confirm both partials render**

Run: `bundle exec rspec spec/requests/completion_kit/dashboard_dismissals_spec.rb`
Expected: PASS (4 examples) — the Turbo Stream now renders the real partials with no missing-template or missing-helper errors.

- [ ] **Step 5: Commit**

```bash
git add app/views/completion_kit/dashboard app/assets/stylesheets/completion_kit/application.css
git commit -m "add worst-metric and failures card partials with ignore flyout"
```

---

## Task 6: Wire the standalone dashboard

**Files:**
- Modify: `standalone/app/controllers/home_controller.rb`
- Modify: `standalone/app/views/home/index.html.erb`

The standalone app has no test suite; this task is verified by booting the server and a Playwright check.

- [ ] **Step 1: Update the home controller**

In `standalone/app/controllers/home_controller.rb`, inside the `if @run_count > 5` block, replace the line:

```ruby
        @failed_review_count = CompletionKit::DashboardStats.failed_review_count(since: 7.days.ago)
```

with:

```ruby
        @failures = CompletionKit::DashboardStats.failures(since: 7.days.ago)
        @ignored_metrics = CompletionKit::DashboardDismissal.metrics
        @ignored_failures = CompletionKit::DashboardDismissal.failures
```

- [ ] **Step 2: Render the worst-metric card partial**

In `standalone/app/views/home/index.html.erb`, replace the entire worst-metric card block — the `<div class="ck-card ck-stat-card ck-rise" style="--rise-delay: 120ms;">` element and everything through its closing `</div>` (the block whose kicker reads "Worst metric · last 7 days") — with:

```erb
      <%= render "completion_kit/dashboard/worst_metric_card",
                 worst_metric: @worst_metric, ignored_metrics: @ignored_metrics %>
```

- [ ] **Step 3: Render the failures card partial**

In the same file, replace the entire failed-reviews card block — the `<div class="ck-card ck-stat-card ck-rise" style="--rise-delay: 180ms;">` element and everything through its closing `</div>` (the block whose kicker reads "Failed reviews · last 7 days") — with:

```erb
      <%= render "completion_kit/dashboard/failures_card",
                 failures: @failures, ignored_failures: @ignored_failures %>
```

- [ ] **Step 4: Boot the server and verify the dashboard**

Run: `cd standalone && bin/rails s` (background), then load `http://localhost:3000`.
Expected: the dashboard shows the Activity, Worst metric, and Failures cards. The worst-metric card shows an "Ignore" button; clicking it removes that metric and surfaces the next worst without a page reload, and an "N ignored" flyout appears. The failures card lists failures with × dismiss controls. Check `standalone/log/development.log` for errors.

- [ ] **Step 5: Commit**

```bash
git add standalone/app/controllers/home_controller.rb standalone/app/views/home/index.html.erb
git commit -m "render dismissible worst-metric and failures cards on the dashboard"
```

---

## Task 7: Full suite + release

**Files:**
- Modify: `lib/completion_kit/version.rb`, `spec/lib/completion_kit_smoke_spec.rb`, `CHANGELOG.md`

- [ ] **Step 1: Run the full suite with coverage**

Run: `bundle exec rspec`
Expected: all examples pass; SimpleCov reports 100% line and 100% branch coverage. If any new `.rb` line/branch is uncovered, add a targeted spec before continuing.

- [ ] **Step 2: Bump the version**

In `lib/completion_kit/version.rb` change `VERSION = "0.5.19"` to `VERSION = "0.5.20"`.
In `spec/lib/completion_kit_smoke_spec.rb` change `expect(CompletionKit::VERSION).to eq("0.5.19")` to `eq("0.5.20")`.

- [ ] **Step 3: Update the changelog**

Add a `## 0.5.20` section at the top of `CHANGELOG.md`'s entries describing: dismissible dashboard alerts — ignore a worst metric (resurfaces on regression) or a failure; unified Failures card replacing the judge-only failed-review count; per-card ignored flyout.

- [ ] **Step 4: Bump both lockfiles**

Run:
```bash
bundle install
cd standalone && bundle install && cd ..
```
Expected: both `Gemfile.lock` files show `completion_kit (0.5.20)`.

- [ ] **Step 5: Commit and push**

```bash
git add lib/completion_kit/version.rb spec/lib/completion_kit_smoke_spec.rb CHANGELOG.md Gemfile.lock standalone/Gemfile.lock
git commit -m "release 0.5.20 — dismissible dashboard alerts"
git push
```

- [ ] **Step 6: After CI is green, release the gem**

Run: `bundle exec rake release`
Expected: gem 0.5.20 published, tag `v0.5.20` pushed, GitHub Release auto-created from the CHANGELOG section.

---

## Self-Review

**Spec coverage:**
- Unified Failures card → Task 3 (`failures`) + Task 5 (`_failures_card`) + Task 6.
- `DashboardDismissal` table/model → Task 1.
- Worst-metric dismissal + regression resurface + stale clear → Task 2.
- Failures permanent dismissal → Task 3 (`failure_dismissal_keys` exclusion).
- Per-card flyout → Task 5 (`ck-flyout` in both partials).
- Turbo Stream auto-update → Task 4 (`refresh.turbo_stream.erb`).
- `failed_review_count` removed → Task 3 (replaced) + Task 6 (controller).
- Tests + 100% coverage → Tasks 1–4 specs + Task 7 Step 1.

**Type consistency:** `worst_metric` returns `:metric/:name/:avg/:response/:score`; partial reads `[:metric].id`, `[:name]`, `[:avg]`, `[:response]`. `failures` returns `{count:, items:[{surface:, record:, run:, cause:, at:}]}`; partial reads `[:count]`, `[:items]`, `item[:surface/:record/:run/:cause]`. `DashboardDismissal.metrics`/`.failures` scopes used identically in controller and `home_controller`. Consistent.

**Placeholder scan:** No TBD/TODO; all code blocks complete. The Task 4 Step 5 note about placeholder partials is resolved by Step 6 creating them and Task 5 filling them.
