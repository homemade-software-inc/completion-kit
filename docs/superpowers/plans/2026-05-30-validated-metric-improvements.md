# Validated Metric Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a user asks to improve a metric, generate a candidate instruction/rubric, re-score it against the cases the user has already reviewed, and show a before/after scoreboard (fixes / keeps / breaks) before they publish — and rename the surrounding "calibration" concept to plain "Agreement".

**Architecture:** A new `MetricImprovementValidator` builds an answer key from the current version's reviewed cases and re-scores a candidate against it via the existing `JudgeService`, producing a tally. A background `MetricSuggestionJob` runs generate → validate → store the summary JSON on the draft `MetricVersion`, then Turbo-broadcasts the result onto the metric page. The scoreboard renders in the existing diff modal; the calibration card is reworded around "Agreement".

**Tech Stack:** Rails 8.1 engine under `CompletionKit`, Solid Queue (`queue_as :llm`), Turbo Streams, RSpec + FactoryBot, SimpleCov 100% line + branch.

**Project conventions (do not violate):**
- No code comments anywhere. No em dashes. No italics.
- All code namespaced under `CompletionKit`.
- 100% line and branch coverage on the FULL suite (`bundle exec rspec`). Single-file runs trip SimpleCov's gate even when all examples pass — judge by "N examples, 0 failures", not the exit code.
- Schema change workflow: add the migration in the engine `db/migrate/`, run `cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate`, commit the generated standalone file AND `standalone/db/schema.rb`, and update the inline test schema in `spec/rails_helper.rb`.
- Start any local worker/server with `DISABLE_SPRING=1`.
- Commit messages: subject line only, or subject plus one short sentence. No co-author/attribution trailer.

**Key existing facts the implementer needs:**
- `MetricVariantGenerator.new(metric, count: 1).call` returns `Variant` structs; `.persist!(variants)` creates draft `MetricVersion`s (`state: "draft", source: "suggestion"`) and returns them.
- `MetricVersion.current.find_by(metric_id:)` is the published current version. `MetricVersion` has `version_label`, `draft?`, `current?`, `rubric_bands` (JSON-serialized).
- `Calibration` has `verdict` (agree/disagree/borderline), `corrected_score` (set on disagree), `metric_version_id`, `response`, `run_id`.
- A response's judge review: `response.reviews.find { |r| r.metric_id == metric.id }`, with `ai_score`.
- `JudgeService.new(config).evaluate(output, expected_output, prompt, criteria:, rubric_text:, input_data:)` returns `{ score:, feedback: }`. Build `config` per response: `ApiConfig.for_model(run.judge_model).merge(judge_model: run.judge_model)`.
- Rubric text for a set of bands: `CompletionKit::Metric.rubric_text_for(CompletionKit::Metric.normalize_rubric_bands(bands))`.
- The metric show page renders `@versions` (a Versions table) and a per-draft diff modal with DOM id `ck-mvdiff-<version.id>`. The calibration card kicker is `Calibration` in `app/views/completion_kit/metrics/show.html.erb`; the stat strip is `app/views/completion_kit/calibrations/_trust_panel.html.erb`.

---

### Task 1: `validation_summary` column on metric_versions

**Files:**
- Create: `db/migrate/20260531000001_add_validation_summary_to_completion_kit_metric_versions.rb`
- Create (generated): `standalone/db/migrate/<timestamp>_add_validation_summary_to_completion_kit_metric_versions.completion_kit.rb`
- Modify: `spec/rails_helper.rb` (the `create_table :completion_kit_metric_versions` block)
- Modify: `app/models/completion_kit/metric_version.rb`
- Test: `spec/models/completion_kit/metric_version_spec.rb`

- [ ] **Step 1: Write the failing test** — add to `spec/models/completion_kit/metric_version_spec.rb`:

```ruby
  it "stores and reads a validation_summary hash" do
    v = create(:completion_kit_metric_version, validation_summary: { "before" => 1, "after" => 4 })
    expect(v.reload.validation_summary).to eq({ "before" => 1, "after" => 4 })
  end

  it "defaults validation_summary to nil" do
    expect(create(:completion_kit_metric_version).validation_summary).to be_nil
  end
```

(If no `:completion_kit_metric_version` factory exists, create `spec/factories/metric_versions.rb`:

```ruby
FactoryBot.define do
  factory :completion_kit_metric_version, class: "CompletionKit::MetricVersion" do
    association :metric, factory: :completion_kit_metric
    instruction { "Rate it." }
    rubric_bands { (1..5).map { |s| { "stars" => s, "description" => "Band #{s}" } } }
    state { "published" }
    current { false }
  end
end
```)

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/models/completion_kit/metric_version_spec.rb -e validation_summary` → FAIL (`unknown attribute` / `NoMethodError`).

- [ ] **Step 3: Inline test schema** — in `spec/rails_helper.rb`, inside `create_table :completion_kit_metric_versions`, add:

```ruby
    t.text :validation_summary
```

- [ ] **Step 4: Engine migration** — create `db/migrate/20260531000001_add_validation_summary_to_completion_kit_metric_versions.rb`:

```ruby
class AddValidationSummaryToCompletionKitMetricVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metric_versions, :validation_summary, :text
  end
end
```

- [ ] **Step 5: Serialize as JSON** — in `app/models/completion_kit/metric_version.rb`, next to the existing `serialize :rubric_bands, coder: JSON`, add:

```ruby
    serialize :validation_summary, coder: JSON
```

- [ ] **Step 6: Install + migrate** — `cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate && cd ..`

- [ ] **Step 7: Run, expect pass** — `bundle exec rspec spec/models/completion_kit/metric_version_spec.rb -e validation_summary` → "2 examples, 0 failures".

- [ ] **Step 8: Commit**

```bash
git add db/migrate spec/rails_helper.rb spec/factories/metric_versions.rb app/models/completion_kit/metric_version.rb spec/models/completion_kit/metric_version_spec.rb standalone/db/migrate standalone/db/schema.rb
git commit -m "Add validation_summary JSON column to metric versions"
```

---

### Task 2: `MetricImprovementValidator` — answer key, tally, scoreboard

**Files:**
- Create: `app/services/completion_kit/metric_improvement_validator.rb`
- Test: `spec/services/completion_kit/metric_improvement_validator_spec.rb`

The validator builds the answer key (current-version, non-borderline reviewed cases, capped at 30 most recent) and, given a per-response score function, classifies each case and summarizes. The score function is injected so the tally is unit-testable without the LLM; the default re-scores via `JudgeService`.

- [ ] **Step 1: Write the failing tests** — create `spec/services/completion_kit/metric_improvement_validator_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::MetricImprovementValidator do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }

  def reviewed(verdict:, ai:, corrected: nil)
    response = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: response, metric: metric, ai_score: ai)
    create(:completion_kit_calibration,
           metric: metric, response: response, run: run,
           metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
           verdict: verdict, corrected_score: corrected, created_by: SecureRandom.uuid)
    response
  end

  it "tallies fixes, keeps, breaks, still-off and before/after against an injected scorer" do
    fix = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    still = reviewed(verdict: "disagree", ai: 5.0, corrected: 1.0)
    keep = reviewed(verdict: "agree", ai: 3.0)
    breaks = reviewed(verdict: "agree", ai: 4.0)
    scores = { fix.id => 2, still.id => 4, keep.id => 3, breaks.id => 1 }

    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(resp, _cand) { scores[resp.id] }).call

    expect(summary["total"]).to eq(4)
    expect(summary["fixes"]).to eq(1)
    expect(summary["still_off"]).to eq(1)
    expect(summary["keeps"]).to eq(1)
    expect(summary["breaks"]).to eq(1)
    expect(summary["before"]).to eq(2)
    expect(summary["after"]).to eq(2)
    expect(summary["rows"].size).to eq(4)
  end

  it "excludes borderlines and caps the answer key at 30 most recent" do
    reviewed(verdict: "borderline", ai: 3.0)
    35.times { reviewed(verdict: "agree", ai: 3.0) }
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 3 }).call
    expect(summary["total"]).to eq(30)
    expect(summary["capped"]).to eq(true)
  end

  it "skips a case whose re-score raises and reports tested count" do
    a = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    b = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    scorer = ->(resp, _c) { resp.id == a.id ? (raise "boom") : 2 }
    summary = described_class.new(metric, candidate, scorer: scorer).call
    expect(summary["tested"]).to eq(1)
    expect(summary["fixes"]).to eq(1)
  end
```

```ruby
  it "only considers reviews on the metric's current version" do
    reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    new_version = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    new_version.publish!
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 2 }).call
    expect(summary["total"]).to eq(0)
  end

  it "returns an empty summary when the metric has no current version" do
    candidate = CompletionKit::MetricVersion.new(metric: metric, instruction: "c", rubric_bands: [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 3 }).call
    expect(summary["total"]).to eq(0)
  end

  it "re-scores via JudgeService when no scorer is injected" do
    resp = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    judge = instance_double(CompletionKit::JudgeService, evaluate: { score: 2, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
    summary = described_class.new(metric, candidate).call
    expect(summary["fixes"]).to eq(1)
  end
end
```

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/services/completion_kit/metric_improvement_validator_spec.rb` → FAIL (uninitialized constant).

- [ ] **Step 3: Implement** — create `app/services/completion_kit/metric_improvement_validator.rb`:

```ruby
module CompletionKit
  class MetricImprovementValidator
    ANSWER_KEY_LIMIT = 30

    def initialize(metric, candidate, scorer: nil)
      @metric = metric
      @candidate = candidate
      @scorer = scorer || method(:rescore)
    end

    def call
      key = answer_key
      rows = []
      key.each do |entry|
        begin
          score = @scorer.call(entry[:response], @candidate)
        rescue StandardError
          next
        end
        rows << classify(entry, score.to_i)
      end
      summarize(rows, key.size, key_capped?)
    end

    private

    def answer_key
      current = MetricVersion.current.find_by(metric_id: @metric.id)
      return [] unless current

      cals = Calibration
             .where(metric_id: @metric.id, metric_version_id: current.id, verdict: %w[agree disagree])
             .includes(response: :reviews)
             .order(created_at: :desc)
             .limit(ANSWER_KEY_LIMIT)
      @key_size_before_cap = Calibration.where(metric_id: @metric.id, metric_version_id: current.id, verdict: %w[agree disagree]).count
      cals.filter_map do |cal|
        response = cal.response
        next unless response&.response_text.present?
        review = response.reviews.find { |r| r.metric_id == @metric.id }
        position = cal.verdict == "disagree" ? cal.corrected_score : review&.ai_score
        next if position.nil?
        { response: response, verdict: cal.verdict, position: position }
      end
    end

    def key_capped?
      @key_size_before_cap.to_i > ANSWER_KEY_LIMIT
    end

    def classify(entry, candidate_score)
      matched = candidate_score == entry[:position].to_i
      outcome = if entry[:verdict] == "disagree"
        matched ? "fix" : "still_off"
      else
        matched ? "keep" : "break"
      end
      {
        "response_id" => entry[:response].id,
        "verdict" => entry[:verdict],
        "position" => entry[:position].to_i,
        "candidate_score" => candidate_score,
        "outcome" => outcome
      }
    end

    def summarize(rows, total, capped)
      fixes = rows.count { |r| r["outcome"] == "fix" }
      keeps = rows.count { |r| r["outcome"] == "keep" }
      breaks = rows.count { |r| r["outcome"] == "break" }
      still_off = rows.count { |r| r["outcome"] == "still_off" }
      agreements = rows.count { |r| r["verdict"] == "agree" }
      {
        "total" => total,
        "tested" => rows.size,
        "capped" => capped,
        "fixes" => fixes,
        "keeps" => keeps,
        "breaks" => breaks,
        "still_off" => still_off,
        "before" => agreements,
        "after" => fixes + keeps,
        "rows" => rows
      }
    end

    def rescore(response, candidate)
      run = response.run
      config = ApiConfig.for_model(run.judge_model).merge(judge_model: run.judge_model)
      rubric_text = Metric.rubric_text_for(Metric.normalize_rubric_bands(candidate.rubric_bands))
      result = JudgeService.new(config).evaluate(
        response.response_text,
        response.expected_output,
        run.prompt&.template,
        criteria: candidate.instruction.to_s,
        rubric_text: rubric_text,
        input_data: response.input_data
      )
      result[:score]
    end
  end
end
```

- [ ] **Step 4: Run, expect pass** — `bundle exec rspec spec/services/completion_kit/metric_improvement_validator_spec.rb` → "4 examples, 0 failures".

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/metric_improvement_validator.rb spec/services/completion_kit/metric_improvement_validator_spec.rb
git commit -m "Add MetricImprovementValidator: re-score a candidate against reviewed cases"
```

Note for the spec reviewer: `total` is the answer-key size (post-cap), `tested` is how many actually re-scored (excludes raises). `before` = agreements (matched by definition originally); `after` = fixes + keeps. `capped` reflects whether more than 30 qualifying cases existed.

---

### Task 3: `MetricSuggestionJob` — generate, validate, store, broadcast

**Files:**
- Create: `app/jobs/completion_kit/metric_suggestion_job.rb`
- Test: `spec/jobs/completion_kit/metric_suggestion_job_spec.rb`

The job runs the existing generator, persists the draft, validates it, stores the summary, and broadcasts a Turbo Stream replacing the status region on the metric page.

- [ ] **Step 1: Write the failing tests** — create `spec/jobs/completion_kit/metric_suggestion_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::MetricSuggestionJob do
  let(:metric) { create(:completion_kit_metric) }

  before { CompletionKit::MetricVersion.ensure_current_for(metric) }

  it "generates a draft, validates it, and stores the summary on the draft" do
    variant = CompletionKit::MetricVariantGenerator::Variant.new(reasoning: "r", instruction: "tighter", rubric_bands: nil)
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([variant])
    allow_any_instance_of(CompletionKit::MetricImprovementValidator).to receive(:call).and_return({ "after" => 3, "before" => 1, "total" => 4 })

    expect { described_class.new.perform(metric.id) }
      .to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").count }.by(1)

    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").last
    expect(draft.validation_summary).to eq({ "after" => 3, "before" => 1, "total" => 4 })
  end

  it "broadcasts a ready status when a draft is produced" do
    variant = CompletionKit::MetricVariantGenerator::Variant.new(reasoning: "r", instruction: "tighter", rubric_bands: nil)
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([variant])
    allow_any_instance_of(CompletionKit::MetricImprovementValidator).to receive(:call).and_return({ "after" => 3 })

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("metric_#{metric.id}_suggestion", hash_including(target: "ck-suggestion-status-#{metric.id}"))

    described_class.new.perform(metric.id)
  end

  it "broadcasts a failure status when the model returns no usable variant" do
    allow_any_instance_of(CompletionKit::MetricVariantGenerator).to receive(:call).and_return([])
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with("metric_#{metric.id}_suggestion", hash_including(target: "ck-suggestion-status-#{metric.id}"))
    expect { described_class.new.perform(metric.id) }
      .not_to change { CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).count }
  end
end
```

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/jobs/completion_kit/metric_suggestion_job_spec.rb` → FAIL (uninitialized constant).

- [ ] **Step 3: Implement** — create `app/jobs/completion_kit/metric_suggestion_job.rb`:

```ruby
module CompletionKit
  class MetricSuggestionJob < ApplicationJob
    queue_as :llm

    def perform(metric_id)
      metric = Metric.find_by(id: metric_id)
      return unless metric

      MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").destroy_all

      variants = MetricVariantGenerator.new(metric, count: 1).call
      if variants.empty?
        broadcast_status(metric, partial: "completion_kit/metrics/suggestion_failed", locals: { metric: metric })
        return
      end

      draft = MetricVariantGenerator.new(metric).persist!(variants).max_by(&:version_number)
      summary = MetricImprovementValidator.new(metric, draft).call
      draft.update!(validation_summary: summary)

      broadcast_status(metric, partial: "completion_kit/metrics/suggestion_ready", locals: { metric: metric, draft: draft })
    end

    private

    def broadcast_status(metric, partial:, locals:)
      Turbo::StreamsChannel.broadcast_replace_to(
        "metric_#{metric.id}_suggestion",
        target: "ck-suggestion-status-#{metric.id}",
        partial: partial,
        locals: locals
      )
    end
  end
end
```

Note: `persist!` is called on a fresh generator instance with the already-generated `variants` (it does not regenerate). The `destroy_all` of prior suggestion drafts matches today's controller behavior.

- [ ] **Step 4: Create the broadcast partials** so the job can render them. Create `app/views/completion_kit/metrics/_suggestion_ready.html.erb`:

```erb
<div id="ck-suggestion-status-<%= metric.id %>" class="ck-suggestion-status ck-suggestion-status--ready">
  <span class="ck-cal-foot__note">Drafted <%= draft.version_label %> and tested it against your reviews.</span>
  <%= link_to "Compare and publish →", metric_path(metric, show_change: draft.id), class: "ck-cal-link" %>
</div>
```

Create `app/views/completion_kit/metrics/_suggestion_failed.html.erb`:

```erb
<div id="ck-suggestion-status-<%= metric.id %>" class="ck-suggestion-status">
  <span class="ck-cal-foot__note">The model returned no usable change. Try again, or review a few more scores first.</span>
</div>
```

- [ ] **Step 5: Run, expect pass** — `bundle exec rspec spec/jobs/completion_kit/metric_suggestion_job_spec.rb` → "3 examples, 0 failures".

- [ ] **Step 6: Commit**

```bash
git add app/jobs/completion_kit/metric_suggestion_job.rb app/views/completion_kit/metrics/_suggestion_ready.html.erb app/views/completion_kit/metrics/_suggestion_failed.html.erb spec/jobs/completion_kit/metric_suggestion_job_spec.rb
git commit -m "Add MetricSuggestionJob: generate, validate, broadcast"
```

---

### Task 4: Controller enqueues the job and shows a pending state

**Files:**
- Modify: `app/controllers/completion_kit/metrics_controller.rb` (`suggest_variants`)
- Modify: `app/views/completion_kit/metrics/show.html.erb` (subscribe to the stream; render the status region)
- Test: `spec/requests/completion_kit/metrics_judge_suggest_spec.rb`

Today `suggest_variants` generates synchronously and redirects. Change it to enqueue `MetricSuggestionJob` and respond with a Turbo Stream that drops a pending state into `ck-suggestion-status-<metric.id>` (web) or a redirect (the `back_to: "edit"` path stays synchronous-feeling via redirect with a notice, but also enqueues — keep edit-page behavior as a redirect with a "drafting" notice).

- [ ] **Step 1: Write/adjust the failing tests** — in `spec/requests/completion_kit/metrics_judge_suggest_spec.rb`, replace the body of the test that today asserts a synchronous draft + redirect with:

```ruby
  it "enqueues the suggestion job and shows a pending state on the metric page" do
    add_disagree
    expect {
      post "/completion_kit/metrics/#{metric.id}/suggest_variants", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    }.to have_enqueued_job(CompletionKit::MetricSuggestionJob).with(metric.id)
    expect(response.body).to include("ck-suggestion-status-#{metric.id}")
    expect(response.body).to include("Drafting a change")
  end

  it "still refuses when there are no disagreements" do
    post "/completion_kit/metrics/#{metric.id}/suggest_variants"
    follow_redirect!
    expect(response.body).to include("Mark at least one case as Disagree")
  end
```

(Keep the existing show-page button-visibility tests; they still pass since the button and its `suggest_variants` form are unchanged.)

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/requests/completion_kit/metrics_judge_suggest_spec.rb -e "enqueues the suggestion job"` → FAIL (still generates synchronously / no status node).

- [ ] **Step 3: Implement the controller** — replace `suggest_variants` in `app/controllers/completion_kit/metrics_controller.rb` with:

```ruby
    def suggest_variants
      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      disagreement_count = Calibration.where(metric_id: @metric.id, verdict: "disagree").count
      if disagreement_count.zero?
        redirect_to target, alert: "Mark at least one case as Disagree before asking the model to suggest a change."
        return
      end

      MetricSuggestionJob.perform_later(@metric.id)

      if params[:back_to] == "edit"
        redirect_to edit_metric_path(@metric), notice: "Drafting a change from your reviews. It will appear here once it's tested."
      else
        answer_key_count = Calibration.where(metric_id: @metric.id, verdict: %w[agree disagree]).count
        render turbo_stream: turbo_stream.replace(
          "ck-suggestion-status-#{@metric.id}",
          partial: "completion_kit/metrics/suggestion_pending",
          locals: { metric: @metric, count: answer_key_count }
        )
      end
    end
```

- [ ] **Step 4: Create the pending partial** — `app/views/completion_kit/metrics/_suggestion_pending.html.erb`:

```erb
<div id="ck-suggestion-status-<%= metric.id %>" class="ck-suggestion-status ck-suggestion-status--pending">
  <span class="ck-cal-foot__note">Drafting a change and testing it against your <%= pluralize(count, "review") %>…</span>
</div>
```

- [ ] **Step 5: Wire the show page** — in `app/views/completion_kit/metrics/show.html.erb`, inside the Agreement card (the `judge_calibration_enabled` section), where the Suggest button lives, ensure the button posts as a Turbo Stream and add the status node + stream subscription. The Suggest button's `button_to` already posts; add `form: { data: { turbo_stream: true } }` is not needed (Turbo handles it). Add near the top of the card body:

```erb
    <%= turbo_stream_from "metric_#{@metric.id}_suggestion" %>
    <div id="ck-suggestion-status-<%= @metric.id %>" class="ck-suggestion-status"></div>
```

Keep the existing Suggest button in the card header. Its POST now returns the pending partial that targets `ck-suggestion-status-<id>`; the job later broadcasts the ready/failed partial to the same target over the subscribed stream.

- [ ] **Step 6: Run, expect pass** — `bundle exec rspec spec/requests/completion_kit/metrics_judge_suggest_spec.rb` → all pass.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/completion_kit/metrics_controller.rb app/views/completion_kit/metrics/show.html.erb app/views/completion_kit/metrics/_suggestion_pending.html.erb spec/requests/completion_kit/metrics_judge_suggest_spec.rb
git commit -m "Run metric suggestions async with a pending state"
```

---

### Task 5: Agreement reframe (retire "calibration" copy)

**Files:**
- Modify: `app/views/completion_kit/metrics/show.html.erb` (card kicker + one-liner)
- Modify: `app/views/completion_kit/calibrations/_trust_panel.html.erb` (measured-state stat)
- Test: `spec/requests/completion_kit/metrics_calibration_spec.rb`

- [ ] **Step 1: Write the failing test** — add to `spec/requests/completion_kit/metrics_calibration_spec.rb`:

```ruby
    it "titles the card Agreement and drops the word Calibration" do
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("Agreement")
      expect(response.body).not_to include(">Calibration<")
      expect(response.body).not_to include("This is a measure of how often the judge's scores match a human reviewer")
    end
```

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/requests/completion_kit/metrics_calibration_spec.rb -e "titles the card Agreement"` → FAIL.

- [ ] **Step 3: Reword the card** — in `app/views/completion_kit/metrics/show.html.erb`, in the Agreement card header, change the kicker from `Calibration` to `Agreement`, and replace the one-liner `<p class="ck-meta-copy">` with:

```erb
    <p class="ck-meta-copy">How often the judge lands on the same score you would. Review its scores to build that signal, and improve the metric to raise it.</p>
```

- [ ] **Step 4: Trim the stat** — in `app/views/completion_kit/calibrations/_trust_panel.html.erb`, replace the measured-state branch (the `else` arm with Agreement / Margin / Read / Sample / Unclear cal-stats) with a plain lead figure plus the borderline chip only:

```erb
  <% else %>
    <span class="ck-cal-stat"><span class="ck-cal-stat__label">Agrees with you</span> <strong class="ck-trust-line__figure">~<%= (stats.agreement_point * 100).round %>%</strong> of <%= stats.sample_size %> reviews</span>
    <% if stats.borderline_rate && stats.borderline_rate > 0 %>
      <% level = stats.borderline_rate > 0.30 ? "danger" : stats.borderline_rate > 0.15 ? "warning" : "ok" %>
      <span class="ck-cal-stat"><span class="ck-cal-stat__label">Unclear</span> <span class="ck-trust-line__borderline ck-trust-line__borderline--<%= level %>"><%= (stats.borderline_rate * 100).round %>%</span></span>
    <% end %>
  <% end %>
```

(The zero-state and counter-state branches keep the version-named copy from 0.10.0.)

- [ ] **Step 5: Run, expect pass** — `bundle exec rspec spec/requests/completion_kit/metrics_calibration_spec.rb` → all pass. Also run `bundle exec rspec spec/services/completion_kit/metric_calibration_stats_spec.rb` to confirm `agreement_point` / `borderline_rate` are unchanged.

- [ ] **Step 6: Commit**

```bash
git add app/views/completion_kit/metrics/show.html.erb app/views/completion_kit/calibrations/_trust_panel.html.erb spec/requests/completion_kit/metrics_calibration_spec.rb
git commit -m "Reframe the calibration card as Agreement"
```

---

### Task 6: The scoreboard in the diff modal + the version-row figure

**Files:**
- Modify: `app/views/completion_kit/metrics/show.html.erb` (diff modal body; version-row figure)
- Create: `app/views/completion_kit/metrics/_validation_scoreboard.html.erb`
- Test: `spec/requests/completion_kit/metrics_judge_versions_spec.rb`

- [ ] **Step 1: Write the failing tests** — add to `spec/requests/completion_kit/metrics_judge_versions_spec.rb`:

```ruby
  def suggestion_draft_with(summary)
    CompletionKit::MetricVersion.ensure_current_for(metric)
    CompletionKit::MetricVersion.create!(
      metric: metric, instruction: "v2 instruction", rubric_bands: metric.rubric_bands || [],
      state: "draft", source: "suggestion", validation_summary: summary
    )
  end

  it "renders the validation scoreboard for a suggestion draft that has a summary" do
    suggestion_draft_with({ "before" => 1, "after" => 4, "total" => 5, "fixes" => 3, "keeps" => 1, "breaks" => 1, "still_off" => 0, "tested" => 5, "capped" => false, "rows" => [] })
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("ck-scoreboard")
    expect(response.body).to include("Matches you on")
    expect(response.body).to include("4 of 5")
    expect(response.body).to include("Breaks")
  end

  it "warns when publishing a net-negative candidate" do
    suggestion_draft_with({ "before" => 3, "after" => 1, "total" => 5, "fixes" => 1, "keeps" => 0, "breaks" => 3, "still_off" => 1, "tested" => 5, "capped" => false, "rows" => [] })
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("Publish anyway?")
  end
```

The first test's positive summary exercises the `net_negative == false` branch of the publish button; the second exercises `net_negative == true`. `ensure_current_for` gives the draft a predecessor so `change_summary_against` is non-nil and the diff modal renders.

- [ ] **Step 2: Run, expect fail** — `bundle exec rspec spec/requests/completion_kit/metrics_judge_versions_spec.rb -e "validation scoreboard"` → FAIL.

- [ ] **Step 3: Create the scoreboard partial** — `app/views/completion_kit/metrics/_validation_scoreboard.html.erb`:

```erb
<% s = summary %>
<div class="ck-scoreboard">
  <p class="ck-scoreboard__headline">Matches you on <strong><%= s["after"] %> of <%= s["total"] %></strong> of your reviews <span class="ck-scoreboard__was">was <%= s["before"] %> of <%= s["total"] %></span></p>
  <ul class="ck-scoreboard__tally">
    <li class="ck-scoreboard__stat ck-scoreboard__stat--fix">Fixes <strong><%= s["fixes"] %></strong></li>
    <li class="ck-scoreboard__stat ck-scoreboard__stat--keep">Keeps <strong><%= s["keeps"] %></strong></li>
    <li class="ck-scoreboard__stat ck-scoreboard__stat--break">Breaks <strong><%= s["breaks"] %></strong></li>
  </ul>
  <% if s["capped"] %>
    <p class="ck-scoreboard__note">Tested against your 30 most recent reviews.</p>
  <% end %>
</div>
```

- [ ] **Step 4: Render the scoreboard in the diff modal** — in `app/views/completion_kit/metrics/show.html.erb`, inside the diff modal `<div class="ck-modal__body">`, before the instruction diff, add:

```erb
          <% if v.draft? && v.validation_summary.present? %>
            <%= render "completion_kit/metrics/validation_scoreboard", summary: v.validation_summary %>
          <% end %>
```

- [ ] **Step 5: Add a net-negative warning to the draft publish button** — in the same modal footer, where the draft's `Publish #{v.version_label} →` button is, set its confirm when the candidate is net-negative. Replace that `button_to` with:

```erb
              <% net_negative = v.validation_summary.present? && (v.validation_summary["after"].to_i < v.validation_summary["before"].to_i || v.validation_summary["breaks"].to_i > v.validation_summary["fixes"].to_i) %>
              <%= button_to "Publish #{v.version_label} →", publish_draft_metric_path(@metric, draft_id: v.id),
                    method: :post, form_class: "inline-block", class: ck_button_classes(:dark),
                    data: net_negative ? { turbo_confirm: "This agrees with you less than the current version. Publish anyway?" } : {} %>
```

- [ ] **Step 6: Add the compact figure to the version row** — in the Versions table, in the version cell (after the `summary` delta button), add for suggestion drafts with a summary:

```erb
                <% if v.draft? && v.validation_summary.present? %>
                  <span class="ck-version-score" title="Matches you on <%= v.validation_summary["after"] %> of <%= v.validation_summary["total"] %> of your reviews"><%= v.validation_summary["after"] %>/<%= v.validation_summary["total"] %></span>
                <% end %>
```

- [ ] **Step 7: Run, expect pass** — `bundle exec rspec spec/requests/completion_kit/metrics_judge_versions_spec.rb` → all pass.

- [ ] **Step 8: Commit**

```bash
git add app/views/completion_kit/metrics/show.html.erb app/views/completion_kit/metrics/_validation_scoreboard.html.erb spec/requests/completion_kit/metrics_judge_versions_spec.rb
git commit -m "Show the validation scoreboard in the diff modal and version row"
```

---

### Task 7: Styles for scoreboard and suggestion status

**Files:**
- Modify: `app/assets/stylesheets/completion_kit/application.css`

- [ ] **Step 1: Append styles** (reuse existing tokens; mono for figures, no italics, no colored left borders):

```css
.ck-suggestion-status:empty { display: none; }
.ck-suggestion-status {
  margin-top: 10px;
  display: flex;
  align-items: baseline;
  gap: 10px;
  flex-wrap: wrap;
}

.ck-scoreboard {
  margin-bottom: 16px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--ck-line);
}
.ck-scoreboard__headline {
  margin: 0 0 8px;
  font-size: 0.95rem;
  color: var(--ck-text);
}
.ck-scoreboard__was {
  font-family: var(--ck-mono);
  font-size: 0.74rem;
  color: var(--ck-muted);
  margin-left: 6px;
}
.ck-scoreboard__tally {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  gap: 18px;
}
.ck-scoreboard__stat {
  font-family: var(--ck-mono);
  font-size: 0.72rem;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--ck-muted);
}
.ck-scoreboard__stat strong { color: var(--ck-text); }
.ck-scoreboard__stat--break strong { color: var(--ck-warning); }
.ck-scoreboard__note {
  margin: 8px 0 0;
  font-size: 0.78rem;
  color: var(--ck-muted);
}
.ck-version-score {
  font-family: var(--ck-mono);
  font-size: 0.74rem;
  color: var(--ck-dim);
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/completion_kit/application.css
git commit -m "Style the validation scoreboard and suggestion status"
```

---

### Final: full suite, coverage, and a visual pass

- [ ] Run the whole suite: `bundle exec rspec`. Confirm 0 failures and 100% line + branch.
- [ ] Likely coverage gaps to cover if flagged: the validator's nil-position skip and no-current-version branch (Task 2 tests cover these); the job's failure branch (Task 3); the controller's `back_to: "edit"` branch (add a request example posting with `back_to: "edit"` and asserting the redirect notice); the net-negative vs positive publish-confirm branches in the modal (add a versions-spec example with a net-negative summary asserting the "Publish anyway?" confirm, and the positive case asserting its absence).
- [ ] Boot the standalone app (`cd standalone && DISABLE_SPRING=1 bin/rails s`), seed a metric with a few disagreements, click Suggest improvements, and confirm: the pending state appears, the job broadcasts the ready state, the diff modal shows the scoreboard, and a net-negative candidate warns on publish. Walk the brand checklist (no em dashes/italics, mono figures, no colored left borders, honest empty states).

---

## Notes for the executor

- The before/after headline stays bold per the design decision ("Matches you on 4 of 5, was 1 of 5"). Do not soften it with disclaimers. The honest guard is the visible Breaks count and the net-negative publish confirm, not hedging copy.
- The answer key is current-version, non-borderline, capped at 30 most recent. Do not fall back to other versions.
- Re-scoring reuses `JudgeService`; do not build a second judging path.
- Keep "calibration" out of user-facing copy; it may remain in internal class names (`MetricCalibrationStats`, `Calibration`) which are not user-visible.
- `MetricSuggestionJob` runs on the `:llm` queue; the local worker must run for the broadcast to fire in development.
