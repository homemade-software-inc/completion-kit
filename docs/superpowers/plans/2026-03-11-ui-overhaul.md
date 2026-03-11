# CompletionKit UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure CompletionKit's data model, routes, controllers, and views to separate concerns (Dataset, Run, Response, Review), fix navigation, and apply consistent UI patterns across all pages.

**Architecture:** Database-first approach — create new tables, migrate data, rename models, then update routes/controllers/views in dependency order. Each chunk produces working software that passes existing tests (adapted for renames).

**Tech Stack:** Rails 7, RSpec, FactoryBot, ERB views, vanilla CSS (no Tailwind in engine).

**Spec:** `docs/superpowers/specs/2026-03-11-ui-overhaul-design.md`

---

## File Structure

### New Files
- `db/migrate/TIMESTAMP_create_completion_kit_datasets.rb`
- `db/migrate/TIMESTAMP_restructure_for_ui_overhaul.rb`
- `app/models/completion_kit/dataset.rb`
- `app/models/completion_kit/run.rb` (replaces test_run.rb)
- `app/models/completion_kit/response.rb` (replaces test_result.rb)
- `app/models/completion_kit/review.rb` (replaces test_result_metric_assessment.rb)
- `app/controllers/completion_kit/datasets_controller.rb`
- `app/controllers/completion_kit/runs_controller.rb` (replaces test_runs_controller.rb)
- `app/controllers/completion_kit/responses_controller.rb` (replaces test_results_controller.rb)
- `app/views/completion_kit/datasets/` (index, show, new, edit, _form)
- `app/views/completion_kit/runs/` (index, show, new, edit, _form)
- `app/views/completion_kit/responses/` (show)
- `spec/factories/datasets.rb`
- `spec/factories/runs.rb` (replaces test_runs.rb)
- `spec/factories/responses.rb` (replaces test_results.rb)
- `spec/factories/reviews.rb` (replaces test_result_metric_assessments.rb)

### Files to Delete (after migration)
- `app/models/completion_kit/test_run.rb`
- `app/models/completion_kit/test_result.rb`
- `app/models/completion_kit/test_result_metric_assessment.rb`
- `app/controllers/completion_kit/test_runs_controller.rb`
- `app/controllers/completion_kit/test_results_controller.rb`
- `app/views/completion_kit/test_runs/` (entire directory)
- `app/views/completion_kit/test_results/` (entire directory)
- `spec/factories/test_runs.rb`
- `spec/factories/test_results.rb`
- `spec/factories/test_result_metric_assessments.rb`

### Files to Modify
- `config/routes.rb`
- `app/models/completion_kit/prompt.rb`
- `app/models/completion_kit/metric.rb`
- `app/models/completion_kit/metric_group.rb`
- `app/controllers/completion_kit/prompts_controller.rb`
- `app/controllers/completion_kit/metrics_controller.rb`
- `app/controllers/completion_kit/metric_groups_controller.rb`
- `app/controllers/completion_kit/provider_credentials_controller.rb`
- `app/helpers/completion_kit/application_helper.rb`
- `app/services/completion_kit/csv_processor.rb`
- `app/services/completion_kit/judge_service.rb`
- `app/assets/stylesheets/completion_kit/application.css`
- `app/views/layouts/completion_kit/application.html.erb`
- `app/views/completion_kit/prompts/` (all 5 files)
- `app/views/completion_kit/metrics/` (all 5 files)
- `app/views/completion_kit/metric_groups/` (all 5 files)
- `app/views/completion_kit/provider_credentials/` (all 4 files)
- `spec/factories/prompts.rb`
- All spec files referencing old model names

---

## Chunk 1: Database Migrations + New Models

### Task 1: Create Dataset model and migration

**Files:**
- Create: `db/migrate/TIMESTAMP_create_completion_kit_datasets.rb`
- Create: `app/models/completion_kit/dataset.rb`
- Create: `spec/factories/datasets.rb`

- [ ] **Step 1: Write factory for Dataset**

```ruby
# spec/factories/datasets.rb
FactoryBot.define do
  factory :dataset, class: "CompletionKit::Dataset" do
    sequence(:name) { |n| "Dataset #{n}" }
    csv_data { "company,message,expected_output\nAcme,Hello,Hi there" }
  end
end
```

- [ ] **Step 2: Write model spec for Dataset**

```ruby
# spec/models/completion_kit/dataset_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::Dataset, type: :model do
  it "validates presence of name" do
    dataset = described_class.new(csv_data: "a,b\n1,2")
    expect(dataset).not_to be_valid
    expect(dataset.errors[:name]).to include("can't be blank")
  end

  it "validates presence of csv_data" do
    dataset = described_class.new(name: "Test")
    expect(dataset).not_to be_valid
    expect(dataset.errors[:csv_data]).to include("can't be blank")
  end

  it "creates a valid dataset" do
    dataset = build(:dataset)
    expect(dataset).to be_valid
  end

  it "reports row_count from csv_data" do
    dataset = build(:dataset, csv_data: "a,b\n1,2\n3,4")
    expect(dataset.row_count).to eq(2)
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/dataset_spec.rb`
Expected: FAIL — table does not exist

- [ ] **Step 4: Create migration**

```ruby
# db/migrate/TIMESTAMP_create_completion_kit_datasets.rb
class CreateCompletionKitDatasets < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_datasets do |t|
      t.string :name, null: false
      t.text :csv_data, null: false
      t.timestamps
    end
  end
end
```

- [ ] **Step 5: Create Dataset model**

```ruby
# app/models/completion_kit/dataset.rb
module CompletionKit
  class Dataset < ApplicationRecord
    has_many :runs, dependent: :restrict_with_error

    validates :name, presence: true
    validates :csv_data, presence: true

    def row_count
      [csv_data.to_s.lines.count - 1, 0].max
    end
  end
end
```

- [ ] **Step 6: Run migration and tests**

Run: `cd examples/demo_app && bin/rails completion_kit:install:migrations && bin/rails db:migrate && cd ../.. && bundle exec rspec spec/models/completion_kit/dataset_spec.rb`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: create Dataset model"
```

### Task 2: Restructure migration — rename tables, move columns

This single migration handles all the schema changes: renames tables, moves columns from Prompt to runs, adds dataset_id, drops deprecated columns.

**Files:**
- Create: `db/migrate/TIMESTAMP_restructure_for_ui_overhaul.rb`

- [ ] **Step 1: Create the migration**

```ruby
# db/migrate/TIMESTAMP_restructure_for_ui_overhaul.rb
class RestructureForUiOverhaul < ActiveRecord::Migration[7.1]
  def up
    # 1. Add dataset_id and judge fields to test_runs
    add_column :completion_kit_test_runs, :dataset_id, :integer
    add_column :completion_kit_test_runs, :judge_model, :string
    unless column_exists?(:completion_kit_test_runs, :metric_group_id)
      add_column :completion_kit_test_runs, :metric_group_id, :integer
    end

    # 2. Migrate existing csv_data from test_runs into datasets (row-by-row for reliable linking)
    execute <<~SQL
      INSERT INTO completion_kit_datasets (name, csv_data, created_at, updated_at)
      SELECT
        COALESCE(name, 'Unnamed') || ' dataset',
        csv_data,
        created_at,
        updated_at
      FROM completion_kit_test_runs
      WHERE csv_data IS NOT NULL AND csv_data != ''
    SQL

    # Link each run to its dataset by matching on csv_data content
    execute <<~SQL
      UPDATE completion_kit_test_runs
      SET dataset_id = (
        SELECT d.id FROM completion_kit_datasets d
        WHERE d.csv_data = completion_kit_test_runs.csv_data
        ORDER BY d.id
        LIMIT 1
      )
      WHERE csv_data IS NOT NULL AND csv_data != ''
    SQL

    # 3. Copy assessment_model and metric_group_id from prompts to test_runs
    if column_exists?(:completion_kit_prompts, :assessment_model)
      execute <<~SQL
        UPDATE completion_kit_test_runs
        SET judge_model = (
          SELECT p.assessment_model FROM completion_kit_prompts p
          WHERE p.id = completion_kit_test_runs.prompt_id
        )
      SQL
    end

    if column_exists?(:completion_kit_prompts, :metric_group_id)
      execute <<~SQL
        UPDATE completion_kit_test_runs
        SET metric_group_id = (
          SELECT p.metric_group_id FROM completion_kit_prompts p
          WHERE p.id = completion_kit_test_runs.prompt_id
        )
        WHERE completion_kit_test_runs.metric_group_id IS NULL
      SQL
    end

    # 4. Rename output_text -> response_text on test_results
    rename_column :completion_kit_test_results, :output_text, :response_text

    # 5. Drop columns from test_results (responses)
    remove_column :completion_kit_test_results, :quality_score if column_exists?(:completion_kit_test_results, :quality_score)
    remove_column :completion_kit_test_results, :human_score if column_exists?(:completion_kit_test_results, :human_score)
    remove_column :completion_kit_test_results, :judge_feedback if column_exists?(:completion_kit_test_results, :judge_feedback)
    remove_column :completion_kit_test_results, :human_feedback if column_exists?(:completion_kit_test_results, :human_feedback)
    remove_column :completion_kit_test_results, :human_reviewer_name if column_exists?(:completion_kit_test_results, :human_reviewer_name)
    remove_column :completion_kit_test_results, :human_reviewed_at if column_exists?(:completion_kit_test_results, :human_reviewed_at)
    remove_column :completion_kit_test_results, :status if column_exists?(:completion_kit_test_results, :status)

    # 6. Drop human review + rubric columns from metric assessments
    remove_column :completion_kit_test_result_metric_assessments, :human_score if column_exists?(:completion_kit_test_result_metric_assessments, :human_score)
    remove_column :completion_kit_test_result_metric_assessments, :human_feedback if column_exists?(:completion_kit_test_result_metric_assessments, :human_feedback)
    remove_column :completion_kit_test_result_metric_assessments, :human_reviewer_name if column_exists?(:completion_kit_test_result_metric_assessments, :human_reviewer_name)
    remove_column :completion_kit_test_result_metric_assessments, :human_reviewed_at if column_exists?(:completion_kit_test_result_metric_assessments, :human_reviewed_at)
    remove_column :completion_kit_test_result_metric_assessments, :rubric_text if column_exists?(:completion_kit_test_result_metric_assessments, :rubric_text)

    # 7. Drop deprecated columns from prompts
    remove_column :completion_kit_prompts, :assessment_model if column_exists?(:completion_kit_prompts, :assessment_model)
    remove_column :completion_kit_prompts, :review_guidance if column_exists?(:completion_kit_prompts, :review_guidance)
    remove_column :completion_kit_prompts, :rubric_text if column_exists?(:completion_kit_prompts, :rubric_text)
    remove_column :completion_kit_prompts, :rubric_bands if column_exists?(:completion_kit_prompts, :rubric_bands)
    remove_column :completion_kit_prompts, :metric_group_id if column_exists?(:completion_kit_prompts, :metric_group_id)

    # 8. Drop csv_data and orphan columns from test_runs
    remove_column :completion_kit_test_runs, :csv_data if column_exists?(:completion_kit_test_runs, :csv_data)
    remove_column :completion_kit_test_runs, :description if column_exists?(:completion_kit_test_runs, :description)
    remove_column :completion_kit_test_runs, :source if column_exists?(:completion_kit_test_runs, :source)
    remove_column :completion_kit_test_runs, :eval_name if column_exists?(:completion_kit_test_runs, :eval_name)

    # 9. Update status values (separate execute calls for SQLite compatibility)
    execute "UPDATE completion_kit_test_runs SET status = 'pending' WHERE status = 'draft'"
    execute "UPDATE completion_kit_test_runs SET status = 'completed' WHERE status = 'evaluated'"

    # 10. Rename tables
    rename_table :completion_kit_test_runs, :completion_kit_runs
    rename_table :completion_kit_test_results, :completion_kit_responses
    rename_table :completion_kit_test_result_metric_assessments, :completion_kit_reviews
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

- [ ] **Step 2: Run migration**

Run: `cd examples/demo_app && bin/rails completion_kit:install:migrations && bin/rails db:migrate`
Expected: Migration succeeds

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: restructure schema — rename tables, move columns, create datasets"
```

### Task 3: Create new model classes

Replace the old model classes with new ones matching the renamed tables and updated associations.

**Files:**
- Create: `app/models/completion_kit/run.rb`
- Create: `app/models/completion_kit/response.rb`
- Create: `app/models/completion_kit/review.rb`
- Modify: `app/models/completion_kit/prompt.rb`
- Modify: `app/models/completion_kit/metric.rb`
- Modify: `app/models/completion_kit/metric_group.rb`
- Delete: `app/models/completion_kit/test_run.rb`
- Delete: `app/models/completion_kit/test_result.rb`
- Delete: `app/models/completion_kit/test_result_metric_assessment.rb`

- [ ] **Step 1: Create Run model**

```ruby
# app/models/completion_kit/run.rb
module CompletionKit
  class Run < ApplicationRecord
    STATUSES = %w[pending generating judging completed failed].freeze

    belongs_to :prompt
    belongs_to :dataset, optional: true
    belongs_to :metric_group, optional: true
    has_many :responses, dependent: :destroy

    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create
    before_validation :set_auto_name, on: :create

    scope :recent, -> { order(created_at: :desc) }

    def judge_configured?
      judge_model.present? && metric_group_id.present?
    end

    def metrics
      metric_group&.metrics || []
    end

    def avg_score
      reviews = Review.joins(:response).where(responses: { run_id: id })
      return nil if reviews.empty?
      scores = reviews.where.not(ai_score: nil).pluck(:ai_score)
      return nil if scores.empty?
      (scores.sum.to_f / scores.size).round(1)
    end

    def generate_responses!
      update!(status: "generating")
      rows = CsvProcessor.process_self(self)
      rows.each do |row|
        filled_prompt = CsvProcessor.apply_variables(prompt, row)
        client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
        result = client.generate_completion(filled_prompt)
        responses.create!(
          input_data: row.to_json,
          response_text: result,
          expected_output: extract_expected_output(row)
        )
      end
      if judge_configured?
        judge_responses!
      else
        update!(status: "completed")
      end
    rescue StandardError => e
      update!(status: "failed")
      errors.add(:base, e.message)
      false
    end

    def judge_responses!
      update!(status: "judging")
      metrics_list = metrics
      responses.each do |response|
        metrics_list.each do |metric|
          config = ApiConfig.for_model(judge_model).merge(judge_model: judge_model)
          judge = JudgeService.new(config)
          result = judge.evaluate(
            response.response_text,
            response.expected_output,
            prompt,
            criteria: metric.criteria,
            evaluation_steps: metric.evaluation_steps,
            rubric_text: metric.display_rubric_text
          )
          response.reviews.create!(
            metric: metric,
            metric_name: metric.name,
            criteria: metric.criteria,
            ai_score: result[:score],
            ai_feedback: result[:feedback],
            status: "evaluated"
          )
        end
      end
      update!(status: "completed")
    rescue StandardError => e
      update!(status: "failed")
      errors.add(:base, e.message)
      false
    end

    private

    def set_default_status
      self.status ||= "pending"
    end

    def set_auto_name
      return if name.present?
      version = prompt&.version_number || 1
      self.name = "#{prompt&.name} v#{version} — #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    end

    def extract_expected_output(row)
      row["expected_output"] || row["expected"]
    end
  end
end
```

- [ ] **Step 2: Create Response model**

```ruby
# app/models/completion_kit/response.rb
module CompletionKit
  class Response < ApplicationRecord
    belongs_to :run
    has_many :reviews, dependent: :destroy

    validates :input_data, presence: true
    validates :response_text, presence: true

    delegate :prompt, to: :run

    def score
      scores = reviews.where.not(ai_score: nil).pluck(:ai_score)
      return nil if scores.empty?
      (scores.sum.to_f / scores.size).round(1)
    end

    def reviewed?
      reviews.exists?
    end
  end
end
```

- [ ] **Step 3: Create Review model**

```ruby
# app/models/completion_kit/review.rb
module CompletionKit
  class Review < ApplicationRecord
    STATUSES = %w[pending evaluated failed].freeze

    belongs_to :response
    belongs_to :metric, optional: true

    validates :metric_name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :ai_score, numericality: { in: 1..5 }, allow_nil: true

    before_validation :set_default_status

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
```

- [ ] **Step 4: Update Prompt model**

Remove `assessment_model`, `metric_group`, `review_guidance`, `rubric_text`, `rubric_bands` references. Update associations.

Modify: `app/models/completion_kit/prompt.rb`

Changes:
- Replace `has_many :test_runs` → `has_many :runs`
- Replace `has_many :test_results, through: :test_runs` → `has_many :responses, through: :runs`
- Remove `has_many :test_result_metric_assessments`
- Remove `belongs_to :metric_group`
- Remove validations for `assessment_model`
- Remove `effective_review_guidance`, `effective_rubric_bands`, `effective_rubric_text` methods
- Remove `human_review_examples` method
- Remove `assessment_metrics` method (metrics now on Run)
- Update `clone_as_new_version`: remove copying of `assessment_model`, `review_guidance`, `rubric_text`, `rubric_bands`, `metric_group_id` — only copy `name`, `description`, `template`, `llm_model`, `family_key`
- Update `set_defaults`: remove any references to `assessment_model`
- Keep: name, description, template, llm_model, version_number, family_key, current, published_at
- Keep: `variables`, `version_label`, `display_name`, `family_versions`, `publish!`
- Keep: `available_models`, `current_for`

- [ ] **Step 5: Update Metric model associations**

Modify: `app/models/completion_kit/metric.rb`

Change: `has_many :test_result_metric_assessments` → `has_many :reviews`

- [ ] **Step 6: Update MetricGroup model associations**

Modify: `app/models/completion_kit/metric_group.rb`

Change: `has_many :prompts` → `has_many :runs`

- [ ] **Step 7: Delete old model files**

```bash
rm app/models/completion_kit/test_run.rb
rm app/models/completion_kit/test_result.rb
rm app/models/completion_kit/test_result_metric_assessment.rb
```

- [ ] **Step 8: Update factories**

Create new factories, delete old ones:

```ruby
# spec/factories/runs.rb
FactoryBot.define do
  factory :run, class: "CompletionKit::Run" do
    association :prompt
    association :dataset
    status { "pending" }
    sequence(:name) { |n| "Run #{n}" }
  end
end
```

```ruby
# spec/factories/responses.rb
FactoryBot.define do
  factory :response, class: "CompletionKit::Response" do
    association :run
    input_data { '{"message": "Hello"}' }
    response_text { "Hi there, how can I help?" }
  end
end
```

```ruby
# spec/factories/reviews.rb
FactoryBot.define do
  factory :review, class: "CompletionKit::Review" do
    association :response
    association :metric
    metric_name { "Accuracy" }
    status { "evaluated" }
    ai_score { 4 }
    ai_feedback { "Good response." }
  end
end
```

Delete old factories:
```bash
rm spec/factories/test_runs.rb
rm spec/factories/test_results.rb
rm spec/factories/test_result_metric_assessments.rb
```

- [ ] **Step 9: Update prompts factory**

Modify: `spec/factories/prompts.rb`

Remove `assessment_model` and `metric_group` from factory defaults. The prompt factory should only set: name, template, llm_model, family_key, version_number.

- [ ] **Step 10: Run all model specs**

Run: `bundle exec rspec spec/models/`
Expected: Fix any failures from renames

- [ ] **Step 11: Commit**

```bash
git add -A && git commit -m "feat: replace TestRun/TestResult/MetricAssessment with Run/Response/Review"
```

### Task 4: Update services

**Files:**
- Modify: `app/services/completion_kit/csv_processor.rb`
- Modify: `app/services/completion_kit/judge_service.rb`

- [ ] **Step 1: Update CsvProcessor**

The `process` method currently takes a `test_run` and accesses `test_run.csv_data`. Now it needs to access `run.dataset.csv_data`. Add a new class method `process_self` that works with the new Run model:

```ruby
def self.process_self(run)
  csv_data = run.dataset.csv_data
  rows = CSV.parse(csv_data, headers: true).map(&:to_h)
  rows
end
```

Keep the old `process` method temporarily for backward compatibility during migration, but the Run model should call `process_self`.

- [ ] **Step 2: Verify JudgeService needs no changes**

JudgeService.evaluate takes `(output, expected_output, prompt, criteria:, evaluation_steps:, rubric_text:, ...)`. The Run model already calls it with these params. No changes needed to JudgeService itself.

- [ ] **Step 3: Run service specs**

Run: `bundle exec rspec spec/services/`
Expected: PASS (or fix failures)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: update CsvProcessor for Dataset model"
```

---

## Chunk 2: Routes + Controllers

### Task 5: Update routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Rewrite routes**

```ruby
# config/routes.rb
CompletionKit::Engine.routes.draw do
  root to: "prompts#index"

  resources :prompts do
    member do
      post :publish
      post :new_version
    end
  end

  resources :datasets
  resources :metrics
  resources :metric_groups

  resources :runs do
    member do
      post :generate
      post :judge
    end
    resources :responses, only: [:show]
  end

  resources :provider_credentials, only: [:index, :new, :create, :edit, :update]
end
```

- [ ] **Step 2: Verify routes compile**

Run: `cd examples/demo_app && bin/rails routes -g completion_kit`
Expected: Shows new route names (runs, responses, datasets, generate, judge)

- [ ] **Step 3: Commit**

```bash
git add config/routes.rb && git commit -m "feat: restructure routes — runs, responses, datasets"
```

### Task 6: Create DatasetsController

**Files:**
- Create: `app/controllers/completion_kit/datasets_controller.rb`

- [ ] **Step 1: Write controller**

```ruby
# app/controllers/completion_kit/datasets_controller.rb
module CompletionKit
  class DatasetsController < ApplicationController
    before_action :set_dataset, only: [:show, :edit, :update, :destroy]

    def index
      @datasets = Dataset.order(created_at: :desc)
    end

    def show
      @runs = @dataset.runs.includes(:prompt).order(created_at: :desc)
    end

    def new
      @dataset = Dataset.new
    end

    def edit; end

    def create
      @dataset = Dataset.new(dataset_params)
      if @dataset.save
        redirect_to datasets_path, notice: "Dataset created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @dataset.update(dataset_params)
        redirect_to @dataset, notice: "Dataset updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @dataset.destroy
      redirect_to datasets_path, notice: "Dataset deleted."
    end

    private

    def set_dataset
      @dataset = Dataset.find(params[:id])
    end

    def dataset_params
      params.require(:dataset).permit(:name, :csv_data)
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: add DatasetsController"
```

### Task 7: Create RunsController (replaces TestRunsController)

**Files:**
- Create: `app/controllers/completion_kit/runs_controller.rb`
- Delete: `app/controllers/completion_kit/test_runs_controller.rb`

- [ ] **Step 1: Write controller**

```ruby
# app/controllers/completion_kit/runs_controller.rb
module CompletionKit
  class RunsController < ApplicationController
    before_action :set_run, only: [:show, :edit, :update, :destroy, :generate, :judge]

    def index
      @runs = Run.includes(:prompt, :dataset, :responses).order(created_at: :desc)
    end

    def show
      @responses = @run.responses.includes(:reviews)
      if @run.judge_configured? && params[:sort] == "score_asc"
        @responses = @responses.left_joins(:reviews)
          .group("completion_kit_responses.id")
          .order(Arel.sql("AVG(completion_kit_reviews.ai_score) ASC NULLS LAST"))
      elsif @run.judge_configured?
        @responses = @responses.left_joins(:reviews)
          .group("completion_kit_responses.id")
          .order(Arel.sql("AVG(completion_kit_reviews.ai_score) DESC NULLS LAST"))
      else
        @responses = @responses.order(:id)
      end
    end

    def new
      @run = Run.new(prompt_id: params[:prompt_id])
      @prompts = Prompt.current_versions
      @datasets = Dataset.order(:name)
      @metric_groups = MetricGroup.order(:name)
    end

    def edit
      @prompts = Prompt.current_versions
      @datasets = Dataset.order(:name)
      @metric_groups = MetricGroup.order(:name)
    end

    def create
      @run = Run.new(run_params)
      if @run.save
        redirect_to @run, notice: "Run created."
      else
        @prompts = Prompt.current_versions
        @datasets = Dataset.order(:name)
        @metric_groups = MetricGroup.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @run.update(run_params)
        redirect_to @run, notice: "Run updated."
      else
        @prompts = Prompt.current_versions
        @datasets = Dataset.order(:name)
        @metric_groups = MetricGroup.order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @run.destroy
      redirect_to runs_path, notice: "Run deleted."
    end

    def generate
      if @run.generate_responses!
        redirect_to @run, notice: "Responses generated and reviewed."
      else
        redirect_to @run, alert: @run.errors.full_messages.to_sentence.presence || "Failed to generate responses."
      end
    end

    def judge
      if params[:run].present?
        @run.update(
          judge_model: params[:run][:judge_model],
          metric_group_id: params[:run][:metric_group_id]
        )
      end
      if @run.judge_responses!
        redirect_to @run, notice: "Responses judged."
      else
        redirect_to @run, alert: @run.errors.full_messages.to_sentence.presence || "Failed to judge responses."
      end
    end

    private

    def set_run
      @run = Run.find(params[:id])
    end

    def run_params
      params.require(:run).permit(:prompt_id, :dataset_id, :judge_model, :metric_group_id)
    end
  end
end
```

- [ ] **Step 2: Delete old controller**

```bash
rm app/controllers/completion_kit/test_runs_controller.rb
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: replace TestRunsController with RunsController"
```

### Task 8: Create ResponsesController (replaces TestResultsController)

**Files:**
- Create: `app/controllers/completion_kit/responses_controller.rb`
- Delete: `app/controllers/completion_kit/test_results_controller.rb`

- [ ] **Step 1: Write controller**

```ruby
# app/controllers/completion_kit/responses_controller.rb
module CompletionKit
  class ResponsesController < ApplicationController
    before_action :set_run
    before_action :set_response

    def show
      @reviews = @response.reviews.includes(:metric)
    end

    private

    def set_run
      @run = Run.find(params[:run_id])
    end

    def set_response
      @response = @run.responses.find(params[:id])
    end
  end
end
```

- [ ] **Step 2: Delete old controller**

```bash
rm app/controllers/completion_kit/test_results_controller.rb
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: replace TestResultsController with ResponsesController"
```

### Task 9: Update PromptsController

**Files:**
- Modify: `app/controllers/completion_kit/prompts_controller.rb`

- [ ] **Step 1: Update controller**

Changes:
- Remove `assessment_model`, `metric_group_id`, `review_guidance`, `rubric_text`, `rubric_bands` from `prompt_params`
- In `show` action, load `@runs = @prompt.runs.includes(:dataset, :responses).order(created_at: :desc)`
- Remove any references to `test_runs` or `test_results`

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: update PromptsController for new model structure"
```

### Task 10: Update helper

**Files:**
- Modify: `app/helpers/completion_kit/application_helper.rb`

- [ ] **Step 1: Update badge/status helpers**

Changes to `ck_badge_classes`:
- Remove `evaluated` status (now just `completed`)
- Add `generating`, `judging` statuses

Changes to `ck_score_kind`:
- Keep the same logic (score thresholds for high/medium/low/pending)

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: update helper for new statuses"
```

---

## Chunk 3: Views — Layout + Prompts + Datasets

### Task 11: Update layout and navigation

**Files:**
- Modify: `app/views/layouts/completion_kit/application.html.erb`

- [ ] **Step 1: Rewrite layout nav**

Nav tabs: Prompts, Metrics, Datasets, Runs, Settings.

Active state detection for each tab:
- Prompts: `request.path.start_with?(prompts_path)` or root
- Metrics: `request.path.start_with?(metrics_path) || request.path.start_with?(metric_groups_path)`
- Datasets: `request.path.start_with?(datasets_path)`
- Runs: `request.path == runs_path` (exact match — run show pages highlight Prompts since they're accessed from the prompt hub)
- Settings: `request.path.start_with?(provider_credentials_path)`

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: update layout nav — Prompts, Metrics, Datasets, Runs, Settings"
```

### Task 12: Rewrite Prompts index

**Files:**
- Modify: `app/views/completion_kit/prompts/index.html.erb`

- [ ] **Step 1: Rewrite as table**

Replace card-based list with table. Columns: Name, Model, Runs (count), Last run (relative time), →.

Header: "Prompts" title + "New prompt" button (primary).

Click row navigates to prompt show. Use `onclick="window.location='...'"` on `<tr>`.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: rewrite prompts index as table"
```

### Task 13: Rewrite Prompts show (The Hub)

**Files:**
- Modify: `app/views/completion_kit/prompts/show.html.erb`

- [ ] **Step 1: Rewrite as single-column hub**

Remove sidebar layout. Single column with:

**Breadcrumb**: Prompts → {name}

**Header**: Name + version badge + model. Actions: Edit (secondary), New version (secondary), Run test (primary, links to `new_run_path(prompt_id: @prompt.id)`).

**Template section**: `<pre class="ck-code">` with prompt template.

**Runs table**: Columns: Run (auto-name), Responses (count), Avg score (badge or "—"), →. Load from `@runs`. Click row navigates to run show.

**Versions section**: Horizontal chips for each family version. Current highlighted. Click navigates to that version's show page.

Remove: metrics section (metrics now on run), description paragraph (keep in edit only), sidebar layout.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: rewrite prompt show as hub with runs table"
```

### Task 14: Update Prompts form

**Files:**
- Modify: `app/views/completion_kit/prompts/_form.html.erb`
- Modify: `app/views/completion_kit/prompts/new.html.erb`
- Modify: `app/views/completion_kit/prompts/edit.html.erb`

- [ ] **Step 1: Simplify form**

Remove fields: assessment_model, metric_group, review_guidance, rubric_text, rubric_bands.

Keep fields: name, description, template, llm_model.

Update new/edit breadcrumbs to be consistent.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: simplify prompt form — remove judge config fields"
```

### Task 15: Create Dataset views

**Files:**
- Create: `app/views/completion_kit/datasets/index.html.erb`
- Create: `app/views/completion_kit/datasets/show.html.erb`
- Create: `app/views/completion_kit/datasets/new.html.erb`
- Create: `app/views/completion_kit/datasets/edit.html.erb`
- Create: `app/views/completion_kit/datasets/_form.html.erb`

- [ ] **Step 1: Create datasets index**

Table layout. Columns: Name, Rows (count), Used in (run count), Created, →.

Header: "Datasets" + "New dataset" button.

- [ ] **Step 2: Create dataset show**

Breadcrumb: Datasets → {name}.

Header with Edit button (secondary).

Sections: CSV preview (`<pre class="ck-code">`), Runs table (runs using this dataset with links).

- [ ] **Step 3: Create dataset form + new/edit wrappers**

Form: name (text input) + csv_data (textarea, code styling).

New: breadcrumb Datasets → New.
Edit: breadcrumb Datasets → {name} → Edit.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add dataset views — index, show, new, edit"
```

---

## Chunk 4: Views — Runs + Responses

### Task 16: Create Run views

**Files:**
- Create: `app/views/completion_kit/runs/index.html.erb`
- Create: `app/views/completion_kit/runs/show.html.erb`
- Create: `app/views/completion_kit/runs/new.html.erb`
- Create: `app/views/completion_kit/runs/edit.html.erb`
- Create: `app/views/completion_kit/runs/_form.html.erb`
- Delete: `app/views/completion_kit/test_runs/` (entire directory)

- [ ] **Step 1: Create runs index (cross-prompt)**

Table layout. Columns: Run (auto-name), Prompt (linked), Responses (count), Avg score, →.

No "New run" button — runs created from prompt page.

- [ ] **Step 2: Create run show**

Breadcrumb: Prompts → {prompt name} → {run name}.

**Header**: Auto-name. Meta line: Model, Dataset (linked to dataset show), Judge + Metrics (if configured) or "No judge configured."

**Collapsible**: Dataset preview.

**Actions**: "Judge responses" button (primary, only when completed and no judge config). Links to judge action with a form to pick judge_model + metric_group.

**Responses section**: Summary cards. Each card:
```erb
<div class="ck-response-card">
  <div class="ck-response-card__header">
    <span class="ck-response-card__number">#<%= index + 1 %></span>
    <% if response.reviewed? %>
      <div class="ck-response-card__scores">
        <div class="ck-metric-bar">
          <% response.reviews.each do |review| %>
            <span class="ck-metric-pip ck-metric-pip--<%= ck_score_kind(review.ai_score) %>">
              <span class="ck-metric-pip__bar"></span>
              <span class="ck-metric-pip__label"><%= review.metric_name %> <strong><%= review.ai_score %></strong></span>
            </span>
          <% end %>
        </div>
        <span class="<%= ck_badge_classes(ck_score_kind(response.score)) %>"><%= response.score %></span>
      </div>
    <% end %>
  </div>
  <div class="ck-response-card__body">
    <p class="ck-response-card__input"><%= truncate(input_summary, length: 120) %></p>
    <p class="ck-response-card__response"><%= truncate(response.response_text, length: 200) %></p>
  </div>
</div>
```

Sort controls: Best first / Worst first (only when judged).

- [ ] **Step 3: Create run form + new/edit**

Form fields: prompt (select), dataset (select), judge_model (select, optional), metric_group (select, optional, shown when judge_model selected).

New: breadcrumb Prompts → {prompt name} → New run. Pre-selects prompt from params.
Edit: breadcrumb Prompts → {prompt name} → {run name} → Edit.

- [ ] **Step 4: Delete old test_runs views**

```bash
rm -rf app/views/completion_kit/test_runs/
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add run views — index, show, new, edit with response cards"
```

### Task 17: Create Response show view

**Files:**
- Create: `app/views/completion_kit/responses/show.html.erb`
- Delete: `app/views/completion_kit/test_results/` (entire directory)

- [ ] **Step 1: Create response show**

Breadcrumb: Prompts → {prompt} → {run} → Response #{n}.

Header: "Response #N" + score badge (if reviewed).

Sections (generous spacing):
- **Input**: `<pre class="ck-code">` with JSON.
- **Response**: `<pre class="ck-code">` with response text.
- **Expected** (if present): `<pre class="ck-code">` + similarity %.

**Review section** (if reviews exist): Per-metric cards stacked vertically. Each card:
```erb
<div class="ck-review-card">
  <div class="ck-review-card__header">
    <span class="ck-review-card__metric"><%= review.metric_name %></span>
    <span class="ck-review-card__stars">
      <% 5.times do |i| %>
        <svg viewBox="0 0 24 24" width="14" height="14" class="ck-star <%= i < review.ai_score.to_i ? 'ck-star--filled' : 'ck-star--empty' %>">
          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
        </svg>
      <% end %>
    </span>
  </div>
  <p class="ck-review-card__feedback"><%= review.ai_feedback %></p>
</div>
```

No human review section.

- [ ] **Step 2: Delete old test_results views**

```bash
rm -rf app/views/completion_kit/test_results/
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: add response show view, remove test_results views"
```

---

## Chunk 5: Views — Metrics, Settings, CSS + Cleanup

### Task 18: Rewrite Metrics views as tables

**Files:**
- Modify: `app/views/completion_kit/metrics/index.html.erb`
- Modify: `app/views/completion_kit/metrics/show.html.erb`

- [ ] **Step 1: Rewrite metrics index**

Table layout. Columns: Name, Criteria (truncated preview), Group (group name or "—"), →.

Header: "Metrics" + "New metric" (primary) + "Groups" (secondary, links to metric_groups_path).

- [ ] **Step 2: Update metrics show**

Single column (already is). Verify no references to old model names. Keep: criteria, evaluation steps, star rubric.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: rewrite metrics index as table"
```

### Task 19: Rewrite Metric Groups views as tables

**Files:**
- Modify: `app/views/completion_kit/metric_groups/index.html.erb`
- Modify: `app/views/completion_kit/metric_groups/show.html.erb`

- [ ] **Step 1: Rewrite as tables**

Index: table with Name, Metrics (count), Used in (run count), →.
Show: group name + description + member metrics listed.

Update breadcrumbs: Metrics → Groups → {name}.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: rewrite metric groups views as tables"
```

### Task 20: Rewrite Provider Credentials views

**Files:**
- Modify: `app/views/completion_kit/provider_credentials/index.html.erb`
- Modify: `app/views/completion_kit/provider_credentials/new.html.erb`
- Modify: `app/views/completion_kit/provider_credentials/edit.html.erb`

- [ ] **Step 1: Rewrite as table**

Index: table with Provider, Status (connected badge), Endpoint, →.

Update breadcrumbs to say "Settings" not "Providers".

Header: "Settings" + "New provider" button.

- [ ] **Step 2: Commit**

```bash
git add -A && git commit -m "feat: rewrite settings views as table, fix breadcrumbs"
```

### Task 21: Update CSS

**Files:**
- Modify: `app/assets/stylesheets/completion_kit/application.css`

- [ ] **Step 1: Add response card styles**

```css
.ck-response-card {
  background: var(--ck-card-bg);
  border: 1px solid var(--ck-border);
  border-radius: 0.5rem;
  padding: 1rem 1.25rem;
  cursor: pointer;
  transition: border-color 0.15s;
}

.ck-response-card:hover {
  border-color: var(--ck-border-hover);
}

.ck-response-card--low {
  border-color: rgba(239, 68, 68, 0.3);
}

.ck-response-card__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.ck-response-card__number {
  font-size: 0.8rem;
  color: var(--ck-muted);
}

.ck-response-card__scores {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.ck-response-card__body {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
}

.ck-response-card__input {
  font-size: 0.875rem;
  color: var(--ck-text);
}

.ck-response-card__response {
  font-size: 0.875rem;
  color: var(--ck-muted);
}
```

- [ ] **Step 2: Add review card styles**

```css
.ck-review-card {
  background: var(--ck-surface);
  border: 1px solid var(--ck-border);
  border-radius: 0.5rem;
  padding: 1rem 1.25rem;
}

.ck-review-card__header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.ck-review-card__metric {
  font-weight: 500;
  color: var(--ck-text);
}

.ck-review-card__feedback {
  font-size: 0.875rem;
  color: var(--ck-muted);
  line-height: 1.5;
}
```

- [ ] **Step 3: Increase spacing globally**

Review all `.ck-card`, `.ck-page-header`, `.ck-stack` spacing. Increase gaps and padding throughout. Target: `gap: 1.5rem` on stacks, `padding: 1.5rem` on cards, `margin-bottom: 2rem` between sections.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add response card + review card CSS, increase spacing"
```

### Task 22: Update all spec files

**Files:**
- Modify: All spec files referencing old model/controller names

- [ ] **Step 1: Find and update all spec references**

Search for `TestRun`, `TestResult`, `TestResultMetricAssessment`, `test_run`, `test_result`, `output_text`, `quality_score`, `human_score` in all spec files. Replace with new names.

Key files likely affected:
- `spec/models/completion_kit/` (model specs)
- `spec/requests/completion_kit/` (request/controller specs)
- `spec/services/completion_kit/` (service specs)

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "fix: update all specs for model renames"
```

### Task 23: Update demo app seed data

**Files:**
- Modify: `examples/demo_app/db/seeds.rb`

- [ ] **Step 1: Update seeds**

Replace TestRun/TestResult creation with Run/Response/Review creation. Add Dataset creation. Remove assessment_model from Prompt creation. Add judge_model and metric_group_id to Run creation.

- [ ] **Step 2: Reset and reseed demo app**

Run: `cd examples/demo_app && bin/rails db:reset`
Expected: Seeds successfully

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: update demo app seeds for new model structure"
```

### Task 24: Final verification

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All green

- [ ] **Step 2: Start demo app and verify manually**

Run: `cd examples/demo_app && bin/rails s`

Verify:
- Prompts index loads as table
- Prompt show is single-column hub with runs table
- Datasets tab works (CRUD)
- Creating a run from prompt page works
- Run show displays response cards
- Response show displays review per metric
- Metrics/Settings pages use tables
- Nav highlights correctly
- Breadcrumbs are consistent

- [ ] **Step 3: Commit any final fixes**

```bash
git add -A && git commit -m "fix: final UI polish"
```
