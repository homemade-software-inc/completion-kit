# Review-grounded Judging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the LLM judge optionally see a small set of past cases on the same metric where a human corrected its score, harvested automatically from calibration disagreements, injected into the judge prompt at scoring time.

**Architecture:** A new flag `judge_examples_from_reviews` (default false) gates the feature. A new selection method `MetricCalibrationExamples.judge_examples_for` returns corrected cases for the current metric version only. `JudgeService` regains an optional `human_examples:` parameter that injects a block between the rubric and the output. `JudgeReviewJob` fetches the examples when the flag is on. The metric page shows the active cases with a per-case mute control.

**Tech Stack:** Rails 8.1 engine namespaced under `CompletionKit`, RSpec + FactoryBot, SimpleCov 100% line and branch coverage, Turbo Streams, heroicons.

**Project conventions (do not violate):**
- No code comments anywhere.
- No em dashes in copy or strings. No italics.
- All code namespaced under `CompletionKit`.
- 100% line and branch coverage. CI enforces it.
- After any schema change: add the migration in the engine `db/migrate/`, run `cd standalone && bin/rails completion_kit:install:migrations`, commit the generated standalone file, AND update the inline test schema in `spec/rails_helper.rb` or specs break.
- Run the local worker with `DISABLE_SPRING=1` if you start one.
- Commit messages: subject line only, or subject plus one short sentence.

**Test commands:**
- Focused: `bundle exec rspec path/to/spec.rb:LINE`
- File: `bundle exec rspec path/to/spec.rb`
- Full suite with coverage gate: `bundle exec rspec`

---

### Task 1: Config flag `judge_examples_from_reviews`

**Files:**
- Modify: `lib/completion_kit.rb:8-34`
- Test: `spec/lib/completion_kit_smoke_spec.rb:68-93`

- [ ] **Step 1: Write the failing test**

Add this expectation inside the existing example "initializes configuration defaults from ENV and registers the precompiled asset" in `spec/lib/completion_kit_smoke_spec.rb`, right after the line `expect(config.medium_quality_threshold).to eq(3)` (currently line 83):

```ruby
    expect(config.judge_examples_from_reviews).to eq(false)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit_smoke_spec.rb -e "initializes configuration defaults"`
Expected: FAIL with `NoMethodError: undefined method 'judge_examples_from_reviews'`

- [ ] **Step 3: Add the accessor and default**

In `lib/completion_kit.rb`, add the accessor after line 15 (`attr_accessor :judge_calibration_enabled`):

```ruby
    attr_accessor :judge_examples_from_reviews
```

In `initialize`, add after line 31 (`@judge_calibration_enabled = true`):

```ruby
      @judge_examples_from_reviews = false
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/completion_kit_smoke_spec.rb -e "initializes configuration defaults"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/completion_kit.rb spec/lib/completion_kit_smoke_spec.rb
git commit -m "Add judge_examples_from_reviews config flag, default off"
```

---

### Task 2: `excluded_from_examples` column on calibrations

**Files:**
- Create: `db/migrate/20260530000001_add_excluded_from_examples_to_completion_kit_calibrations.rb`
- Create (generated): `standalone/db/migrate/<timestamp>_add_excluded_from_examples_to_completion_kit_calibrations.completion_kit.rb`
- Modify: `spec/rails_helper.rb:246-256`
- Test: `spec/models/completion_kit/calibration_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/completion_kit/calibration_spec.rb` (create the file if it does not exist, with `require "rails_helper"` and the `RSpec.describe CompletionKit::Calibration do ... end` wrapper):

```ruby
  it "defaults excluded_from_examples to false" do
    calibration = create(:completion_kit_calibration)
    expect(calibration.excluded_from_examples).to eq(false)
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/calibration_spec.rb -e "defaults excluded_from_examples"`
Expected: FAIL with `NoMethodError: undefined method 'excluded_from_examples'` (the inline test schema has no such column yet)

- [ ] **Step 3: Add the column to the inline test schema**

In `spec/rails_helper.rb`, inside the `create_table :completion_kit_calibrations` block, add after the line `t.text :note` (currently line 254):

```ruby
    t.boolean :excluded_from_examples, null: false, default: false
```

- [ ] **Step 4: Write the engine migration**

Create `db/migrate/20260530000001_add_excluded_from_examples_to_completion_kit_calibrations.rb`:

```ruby
class AddExcludedFromExamplesToCompletionKitCalibrations < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_calibrations, :excluded_from_examples, :boolean, null: false, default: false
  end
end
```

- [ ] **Step 5: Install the migration into the standalone app and run it**

```bash
cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate && cd ..
```

Expected: a new file `standalone/db/migrate/<timestamp>_add_excluded_from_examples_to_completion_kit_calibrations.completion_kit.rb` is generated, and `db:migrate` runs it cleanly.

- [ ] **Step 6: Run test to verify it passes**

Run: `bundle exec rspec spec/models/completion_kit/calibration_spec.rb -e "defaults excluded_from_examples"`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add db/migrate spec/rails_helper.rb spec/models/completion_kit/calibration_spec.rb standalone/db/migrate standalone/db/schema.rb
git commit -m "Add excluded_from_examples column to calibrations"
```

---

### Task 3: Selection method `MetricCalibrationExamples.judge_examples_for`

**Files:**
- Modify: `app/services/completion_kit/metric_variant_generator.rb:120-155`
- Test: `spec/services/completion_kit/metric_calibration_examples_spec.rb`

This task also extracts the shared row-mapping (`map_examples`) used by both the existing `calibrations_for` and the new `judge_examples_for`, and adds `id: cal.id` to the mapped row so the UI can reference the calibration. Per project convention, the per-task code-quality review must confirm this reorganization.

- [ ] **Step 1: Write the failing tests**

Create `spec/services/completion_kit/metric_calibration_examples_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::MetricCalibrationExamples do
  def disagreement(metric, score: 2.0, judge: 4.0, response: nil, excluded: false)
    response ||= create(:completion_kit_response)
    create(:completion_kit_review, response: response, metric: metric, ai_score: judge, ai_feedback: "judge said")
    create(:completion_kit_calibration,
           metric: metric, response: response, run: response.run,
           verdict: "disagree", corrected_score: score, note: "too high",
           excluded_from_examples: excluded)
  end

  let(:metric) { create(:completion_kit_metric) }

  it "returns corrected cases for the current version with judge and human scores" do
    cal = disagreement(metric)
    examples = described_class.judge_examples_for(metric)
    expect(examples.size).to eq(1)
    expect(examples.first[:id]).to eq(cal.id)
    expect(examples.first[:judge_score]).to eq(4.0)
    expect(examples.first[:human_score]).to eq(2.0)
    expect(examples.first[:human_note]).to eq("too high")
    expect(examples.first[:output]).to eq(cal.response.response_text)
  end

  it "returns an empty array when the metric has no current version" do
    expect(described_class.judge_examples_for(create(:completion_kit_metric))).to eq([])
  end

  it "skips muted cases" do
    disagreement(metric, excluded: true)
    expect(described_class.judge_examples_for(metric)).to eq([])
  end

  it "skips the response being scored" do
    response = create(:completion_kit_response)
    disagreement(metric, response: response)
    expect(described_class.judge_examples_for(metric, exclude_response_id: response.id)).to eq([])
  end

  it "caps the result at the default limit of 5" do
    6.times { disagreement(metric) }
    expect(described_class.judge_examples_for(metric).size).to eq(5)
  end

  it "does not fall back to corrections from a superseded version" do
    disagreement(metric)
    newer = CompletionKit::MetricVersion.create!(
      metric: metric, instruction: "newer", rubric_bands: metric.rubric_bands,
      state: "draft", source: "edit"
    )
    newer.publish!
    expect(described_class.judge_examples_for(metric)).to eq([])
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/metric_calibration_examples_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'judge_examples_for'`

- [ ] **Step 3: Implement the selection method and extract the shared mapper**

Replace the `MetricCalibrationExamples` module in `app/services/completion_kit/metric_variant_generator.rb` (currently lines 120-155) with:

```ruby
  module MetricCalibrationExamples
    DEFAULT_JUDGE_EXAMPLE_LIMIT = 5

    module_function

    def for(metric, limit: 8)
      disagreements_for(metric, limit: limit)
    end

    def disagreements_for(metric, limit: 8)
      calibrations_for(metric, verdict: "disagree", limit: limit)
    end

    def borderlines_for(metric, limit: 6)
      calibrations_for(metric, verdict: "borderline", limit: limit)
    end

    def judge_examples_for(metric, exclude_response_id: nil, limit: DEFAULT_JUDGE_EXAMPLE_LIMIT)
      current_version = MetricVersion.current.find_by(metric_id: metric.id)
      return [] unless current_version

      relation = Calibration
                 .where(metric_id: metric.id, metric_version_id: current_version.id, excluded_from_examples: false)
                 .where.not(corrected_score: nil)
      relation = relation.where.not(response_id: exclude_response_id) if exclude_response_id
      map_examples(relation.includes(response: :reviews).order(created_at: :desc).limit(limit), metric)
    end

    def calibrations_for(metric, verdict:, limit:)
      base = Calibration.where(metric_id: metric.id, verdict: verdict)
      current_version = MetricVersion.current.find_by(metric_id: metric.id)
      scoped = current_version ? base.where(metric_version_id: current_version.id) : base
      effective = scoped.exists? ? scoped : base
      map_examples(effective.includes(response: :reviews).order(created_at: :desc).limit(limit), metric)
    end

    def map_examples(relation, metric)
      relation.map do |cal|
        review = cal.response.reviews.find { |r| r.metric_id == metric.id }
        {
          id: cal.id,
          input: cal.response.input_data,
          output: cal.response.response_text,
          judge_score: review&.ai_score,
          judge_feedback: review&.ai_feedback,
          human_score: cal.corrected_score,
          human_note: cal.note
        }
      end
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/metric_calibration_examples_spec.rb`
Expected: PASS

- [ ] **Step 5: Run the variant generator spec to confirm no regression**

Run: `bundle exec rspec spec/services/completion_kit/metric_variant_generator_spec.rb`
Expected: PASS (the extraction and the added `id:` key must not break the rewrite path)

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/metric_variant_generator.rb spec/services/completion_kit/metric_calibration_examples_spec.rb
git commit -m "Add judge_examples_for selection for review-grounded judging"
```

---

### Task 4: Inject `human_examples` into the judge prompt

**Files:**
- Modify: `app/services/completion_kit/judge_service.rb:13-54`
- Test: `spec/services/completion_kit/judge_service_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/services/completion_kit/judge_service_spec.rb` before the final closing `end`:

```ruby
  it "injects human examples between the rubric and the output to evaluate, with and without a note" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("Reviewed examples", "The judge scored this 4.0/5", "corrected it to 2.0/5", "way off", "corrected it to 5.0/5."),
      model: "gpt-4.1"
    ).and_return("Score: 2\nFeedback: Recalibrated")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    result = service.evaluate(
      "actual", nil, "prompt",
      human_examples: [
        { output: "some output", judge_score: 4.0, human_score: 2.0, human_note: "way off" },
        { output: "other output", judge_score: 1.0, human_score: 5.0, human_note: nil }
      ]
    )
    expect(result).to eq(score: 2.0, feedback: "Recalibrated")
  end

  it "produces a prompt with no examples block when human_examples is nil" do
    captured = nil
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion) do |prompt, **_|
      captured = prompt
      "Score: 3\nFeedback: fine"
    end
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    described_class.new.evaluate("actual")
    expect(captured).not_to include("Reviewed examples")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/judge_service_spec.rb -e "human examples"`
Expected: FAIL (the prompt has no "Reviewed examples" block and `evaluate` ignores `human_examples`)

- [ ] **Step 3: Implement the injection**

In `app/services/completion_kit/judge_service.rb`, change the `evaluate` signature (line 13) to accept `human_examples:` and pass it through:

```ruby
    def evaluate(output, expected_output = nil, prompt = nil, criteria: nil, rubric_text: nil, input_data: nil, human_examples: nil, **_extras)
      raise CompletionKit::ConfigurationError, "Judge not configured" unless @judge_client.configured?

      judge_prompt = build_judge_prompt(output, expected_output, prompt,
        criteria: criteria,
        rubric_text: rubric_text,
        input_data: input_data,
        human_examples: human_examples)

      response = @judge_client.generate_completion(judge_prompt, model: @judge_model)
      raise StandardError, response if response.start_with?("Error:")
      parse_judge_response(response)
    end
```

Change `build_judge_prompt` (line 28) to accept `human_examples:` and inject the block between the criteria and the "Original prompt" section:

```ruby
    def build_judge_prompt(output, expected_output, prompt, criteria: nil, rubric_text: nil, input_data: nil, human_examples: nil)
      judge_prompt = <<~PROMPT
        You are an expert evaluator. You MUST respond with ONLY two lines in this exact format, nothing else:

        Score: <integer from 1 to 5>
        Feedback: <one sentence explaining why>

        Do not include any other text, markdown, or explanation. Just those two lines.

        Use this rubric to choose the score:
        #{rubric_text.presence || CompletionKit::Metric.default_rubric_text}
      PROMPT

      if criteria.present?
        judge_prompt += "\nCriteria: #{criteria}\n"
      end

      judge_prompt += human_examples_block(human_examples)

      judge_prompt += <<~PROMPT

        Original prompt: #{prompt || "Not provided"}
        #{input_data.present? ? "Input data: #{input_data}" : ""}
        #{expected_output.present? ? "Expected output: #{expected_output}" : ""}
        AI output to evaluate: #{output}
      PROMPT

      judge_prompt
    end

    def human_examples_block(examples)
      return "" if examples.blank?

      lines = ["", "Reviewed examples where a human corrected the judge on this metric. Weigh them when scoring:"]
      examples.each_with_index do |example, index|
        line = "Example #{index + 1}: Output: #{example[:output].to_s.truncate(200)}. The judge scored this #{example[:judge_score]}/5. A reviewer corrected it to #{example[:human_score]}/5"
        line += example[:human_note].to_s.present? ? ": #{example[:human_note].to_s.truncate(160)}" : "."
        lines << line
      end
      lines.join("\n") + "\n"
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/judge_service_spec.rb`
Expected: PASS (all existing examples plus the two new ones)

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/judge_service.rb spec/services/completion_kit/judge_service_spec.rb
git commit -m "Inject review-grounded examples into the judge prompt"
```

---

### Task 5: Wire the job to pass examples when the flag is on

**Files:**
- Modify: `app/jobs/completion_kit/judge_review_job.rb:44-79`
- Test: `spec/jobs/completion_kit/judge_review_job_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/jobs/completion_kit/judge_review_job_spec.rb` (match the existing setup style in that file for building a run, response, and metric; reuse whatever factory helpers the file already defines). Wrap flag mutation so it is restored:

```ruby
  describe "review-grounded examples" do
    around do |example|
      original_examples = CompletionKit.config.judge_examples_from_reviews
      original_calibration = CompletionKit.config.judge_calibration_enabled
      example.run
    ensure
      CompletionKit.config.judge_examples_from_reviews = original_examples
      CompletionKit.config.judge_calibration_enabled = original_calibration
    end

    let(:run) { create(:completion_kit_run, judge_model: "gpt-4.1") }
    let(:response) { create(:completion_kit_response, run: run) }
    let(:metric) { create(:completion_kit_metric) }

    before do
      allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    end

    it "passes human_examples to the judge when the flag is on" do
      CompletionKit.config.judge_examples_from_reviews = true
      examples = [{ output: "x", judge_score: 4.0, human_score: 2.0, human_note: "n" }]
      allow(CompletionKit::MetricCalibrationExamples).to receive(:judge_examples_for)
        .with(metric, exclude_response_id: response.id).and_return(examples)

      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: examples))
        .and_return(score: 2.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end

    it "passes no examples when the flag is off" do
      CompletionKit.config.judge_examples_from_reviews = false
      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: nil))
        .and_return(score: 3.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end

    it "passes no examples when calibration is disabled" do
      CompletionKit.config.judge_examples_from_reviews = true
      CompletionKit.config.judge_calibration_enabled = false
      judge = instance_double(CompletionKit::JudgeService)
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      expect(judge).to receive(:evaluate)
        .with(anything, anything, anything, hash_including(human_examples: nil))
        .and_return(score: 3.0, feedback: "ok")

      described_class.new.perform(response.id, metric.id, run.id)
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/jobs/completion_kit/judge_review_job_spec.rb -e "review-grounded examples"`
Expected: FAIL because `evaluate` is currently called without a `human_examples:` key

- [ ] **Step 3: Implement the wiring**

In `app/jobs/completion_kit/judge_review_job.rb`, change the `evaluate` call inside `perform` (currently lines 55-62) to pass `human_examples:`:

```ruby
      evaluation = judge.evaluate(
        response.response_text,
        response.expected_output,
        run.prompt&.template,
        criteria: metric.instruction.to_s,
        rubric_text: metric.display_rubric_text,
        input_data: response.input_data,
        human_examples: review_examples_for(metric, response)
      )
```

Add this private method (place it just above `confirm_judging_capability`, after the `private` keyword on line 81):

```ruby
    def review_examples_for(metric, response)
      return nil unless CompletionKit.config.judge_calibration_enabled
      return nil unless CompletionKit.config.judge_examples_from_reviews

      MetricCalibrationExamples.judge_examples_for(metric, exclude_response_id: response.id)
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/completion_kit/judge_review_job_spec.rb`
Expected: PASS (new examples plus all existing job examples)

- [ ] **Step 5: Commit**

```bash
git add app/jobs/completion_kit/judge_review_job.rb spec/jobs/completion_kit/judge_review_job_spec.rb
git commit -m "Feed review-grounded examples to the judge job behind the flag"
```

---

### Task 6: Exclude action and `@guiding_examples` in show

**Files:**
- Modify: `config/routes.rb:21-25`
- Modify: `app/controllers/completion_kit/metrics_controller.rb:4` and `:37-42`
- Test: `spec/requests/completion_kit/metric_review_examples_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/requests/completion_kit/metric_review_examples_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Metric review-grounded examples", type: :request do
  around do |example|
    original = CompletionKit.config.judge_examples_from_reviews
    CompletionKit.config.judge_examples_from_reviews = true
    example.run
  ensure
    CompletionKit.config.judge_examples_from_reviews = original
  end

  let(:metric) { create(:completion_kit_metric) }

  def disagreement(metric)
    response = create(:completion_kit_response)
    create(:completion_kit_review, response: response, metric: metric, ai_score: 4.0)
    create(:completion_kit_calibration,
           metric: metric, response: response, run: response.run,
           verdict: "disagree", corrected_score: 2.0, note: "too high")
  end

  it "mutes a case and removes it from the guiding set" do
    cal = disagreement(metric)
    expect(CompletionKit::MetricCalibrationExamples.judge_examples_for(metric).size).to eq(1)

    post exclude_example_metric_path(metric, calibration_id: cal.id)

    expect(response).to have_http_status(:ok)
    expect(cal.reload.excluded_from_examples).to eq(true)
    expect(CompletionKit::MetricCalibrationExamples.judge_examples_for(metric)).to eq([])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/metric_review_examples_spec.rb`
Expected: FAIL with `NameError`/`NoMethodError` on `exclude_example_metric_path` (route does not exist)

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `resources :metrics do ... member do ... end`, add `post :exclude_example` to the member block (currently lines 21-25):

```ruby
    member do
      post :publish_draft
      post :suggest_variants
      delete :dismiss_suggestion
      post :exclude_example
    end
```

- [ ] **Step 4: Add the action and the before_action entry**

In `app/controllers/completion_kit/metrics_controller.rb`, add `:exclude_example` to the `set_metric` before_action list (line 4):

```ruby
    before_action :set_metric, only: [:show, :edit, :update, :destroy, :publish_draft, :suggest_variants, :dismiss_suggestion, :exclude_example]
```

Set `@guiding_examples` in `show` (currently lines 37-42). Replace the `show` method body with:

```ruby
    def show
      @edit_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @suggestion_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @improve_disagreement_count = Calibration.where(metric_id: @metric.id, verdict: "disagree").count
      @versions = MetricVersion.where(metric_id: @metric.id).order(version_number: :desc).to_a
      @guiding_examples = CompletionKit.config.judge_examples_from_reviews ? MetricCalibrationExamples.judge_examples_for(@metric) : []
    end
```

Add the `exclude_example` action. Place it after `dismiss_suggestion` (the implementer should locate `dismiss_suggestion`, currently near line 140, and add this method after it, still as a public action):

```ruby
    def exclude_example
      calibration = Calibration.where(metric_id: @metric.id).find(params[:calibration_id])
      calibration.update!(excluded_from_examples: true)
      render turbo_stream: turbo_stream.replace(
        "ck-guiding-#{@metric.id}",
        partial: "completion_kit/metrics/guiding_examples",
        locals: { metric: @metric, examples: MetricCalibrationExamples.judge_examples_for(@metric) }
      )
    end
```

Note: the partial referenced here is created in Task 7. This request spec asserts the row is muted and the http status, so it passes once the partial exists. If running tasks strictly in order, this spec will fail to render until Task 7 adds the partial. To keep Task 6 green on its own, the implementer should create a minimal placeholder partial `app/views/completion_kit/metrics/_guiding_examples.html.erb` containing only the wrapper div in this task, then flesh it out in Task 7:

```erb
<div id="ck-guiding-<%= metric.id %>" class="ck-guiding"></div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/metric_review_examples_spec.rb`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/completion_kit/metrics_controller.rb app/views/completion_kit/metrics/_guiding_examples.html.erb spec/requests/completion_kit/metric_review_examples_spec.rb
git commit -m "Add exclude_example action and guiding-examples loading"
```

---

### Task 7: Guiding-examples section on the metric page

**Files:**
- Modify: `app/views/completion_kit/metrics/_guiding_examples.html.erb`
- Modify: `app/views/completion_kit/metrics/show.html.erb:179-204`
- Modify: `app/assets/stylesheets/completion_kit/application.css`
- Test: `spec/requests/completion_kit/metric_review_examples_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/requests/completion_kit/metric_review_examples_spec.rb` before the final closing `end`:

```ruby
  it "shows the guiding section with active cases on the metric page" do
    disagreement(metric)
    get metric_path(metric)
    expect(response.body).to include("ck-guiding-#{metric.id}")
    expect(response.body).to include("guiding the judge")
  end

  it "hides the guiding section when the flag is off" do
    CompletionKit.config.judge_examples_from_reviews = false
    disagreement(metric)
    get metric_path(metric)
    expect(response.body).not_to include("guiding the judge")
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/requests/completion_kit/metric_review_examples_spec.rb -e "guiding section"`
Expected: FAIL (the placeholder partial has no copy, and show.html.erb does not render it yet)

- [ ] **Step 3: Flesh out the partial**

Replace `app/views/completion_kit/metrics/_guiding_examples.html.erb` with:

```erb
<div id="ck-guiding-<%= metric.id %>" class="ck-guiding">
  <% if examples.any? %>
    <p class="ck-cal-foot__note"><%= pluralize(examples.size, "reviewed case") %> guiding the judge on this metric during runs.</p>
    <ul class="ck-guiding__list">
      <% examples.each do |example| %>
        <li class="ck-guiding__item">
          <span class="ck-guiding__scores"><%= example[:judge_score] %> &rarr; <%= example[:human_score] %></span>
          <span class="ck-guiding__output"><%= truncate(example[:output].to_s, length: 120) %></span>
          <%= button_to exclude_example_metric_path(metric, calibration_id: example[:id]),
                method: :post, form_class: "inline-block", class: "ck-icon-btn",
                title: "Stop using this case", "aria-label": "Stop using this case",
                data: { turbo_confirm: "Stop using this corrected case to guide the judge?" } do %><%= heroicon_tag "x-mark", variant: :outline, size: 16, "aria-hidden": "true" %><% end %>
        </li>
      <% end %>
    </ul>
  <% end %>
</div>
```

- [ ] **Step 4: Render it inside the Calibration card**

In `app/views/completion_kit/metrics/show.html.erb`, inside the `if CompletionKit.config.judge_calibration_enabled` Calibration section, add the render right after the `trust_panel` render block (after the closing `%>` on line 185, before `<% draft = @suggestion_draft || @edit_draft %>`):

```erb
    <% if CompletionKit.config.judge_examples_from_reviews %>
      <%= render "completion_kit/metrics/guiding_examples", metric: @metric, examples: @guiding_examples %>
    <% end %>
```

- [ ] **Step 5: Add the styles**

Append to `app/assets/stylesheets/completion_kit/application.css`:

```css
.ck-guiding {
  margin-top: 0.75rem;
}

.ck-guiding__list {
  list-style: none;
  margin: 0.5rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
}

.ck-guiding__item {
  display: flex;
  align-items: center;
  gap: 0.625rem;
}

.ck-guiding__scores {
  font-family: var(--ck-mono);
  font-size: 0.8125rem;
  color: var(--ck-dim);
  white-space: nowrap;
}

.ck-guiding__output {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--ck-dim);
  font-size: 0.875rem;
}

.ck-guiding__item .ck-icon-btn {
  width: 2rem;
  height: 2rem;
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/requests/completion_kit/metric_review_examples_spec.rb`
Expected: PASS

- [ ] **Step 7: Walk the UI checklist and verify in the browser**

Confirm against the project's pre-push UI checklist: no em dashes, no italics, JetBrains Mono for the score pair, alignment, honest empty state (no content when there are no cases), brand icon button sizing. Start the server (`cd standalone && bin/rails s`), open a metric with at least one disagreement while `judge_examples_from_reviews` is on, and confirm the muting updates the section without a full page reload.

- [ ] **Step 8: Commit**

```bash
git add app/views/completion_kit/metrics/_guiding_examples.html.erb app/views/completion_kit/metrics/show.html.erb app/assets/stylesheets/completion_kit/application.css spec/requests/completion_kit/metric_review_examples_spec.rb
git commit -m "Show review-grounded cases guiding the judge on the metric page"
```

---

### Final: Full suite and coverage gate

- [ ] Run the whole suite: `bundle exec rspec`
- [ ] Confirm 0 failures and 100% line and branch coverage (CI gate). The branches most at risk are the `human_examples_block` note-absent path, the `judge_examples_for` no-current-version path, and the `review_examples_for` calibration-disabled path. Each has an explicit example in the tasks above. If coverage still drops, add focused examples for whatever line or branch CI flags.
- [ ] Confirm no stray `excluded_from_examples` schema drift between `spec/rails_helper.rb` and `standalone/db/schema.rb`.

---

## Notes for the executor

- The feature is dark by default. Nothing changes for existing users until they set `config.judge_examples_from_reviews = true`. Verify a default-off run produces a byte-identical judge prompt (Task 4 covers this).
- The selection deliberately does NOT fall back to older-version corrections, unlike `calibrations_for`. The no-fallback test in Task 3 guards this. Do not "fix" it to match the rewrite path.
- `human_examples` flows as `nil` when off, which makes `human_examples_block` return an empty string. Keep that path intact.
- Muting is one-directional in v1 (no un-mute). Do not add an un-mute control.
