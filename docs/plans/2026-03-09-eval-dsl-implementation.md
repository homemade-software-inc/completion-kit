# Eval DSL Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Ruby DSL and rake task so engineers can define prompt evals in code, run them in CI, and gate deploys on per-metric quality thresholds.

**Architecture:** New eval registry (`CompletionKit.define_eval`) stores eval definitions. A runner loads `evals/**/*_eval.rb` from the host app, executes each eval by generating outputs and scoring them via existing services, stores results as test runs, and compares scores to thresholds. A formatter prints RSpec-style terminal output.

**Tech Stack:** Ruby, Rails engine, existing CompletionKit services (JudgeService, CsvProcessor, LlmClient)

---

### Task 1: Migration — Add key to metrics, source/eval_name to test_runs

**Files:**
- Create: `db/migrate/20260309000000_add_eval_dsl_fields.rb`
- Modify: `app/models/completion_kit/metric.rb`
- Modify: `app/models/completion_kit/test_run.rb`
- Modify: `spec/rails_helper.rb` (in-memory schema)

**Step 1: Write the migration**

```ruby
class AddEvalDslFields < ActiveRecord::Migration[7.0]
  def change
    add_column :completion_kit_metrics, :key, :string
    add_index :completion_kit_metrics, :key, unique: true

    add_column :completion_kit_test_runs, :source, :string, default: "ui"
    add_column :completion_kit_test_runs, :eval_name, :string
  end
end
```

**Step 2: Update the in-memory test schema in spec/rails_helper.rb**

Add `t.string :key` to the `completion_kit_metrics` table definition.
Add `t.string :source, default: "ui"` and `t.string :eval_name` to the `completion_kit_test_runs` table definition.

**Step 3: Update Metric model**

Add to `app/models/completion_kit/metric.rb`:
- `validates :key, uniqueness: true, allow_nil: true`
- `before_validation :generate_key` callback
- Private method `generate_key` that sets `self.key ||= name&.parameterize(separator: "_")` when name is present

**Step 4: Update TestRun model**

Add to `app/models/completion_kit/test_run.rb`:
- Update `STATUSES` — no change needed (statuses stay the same)
- Add `validates :source, inclusion: { in: %w[ui eval_dsl] }, allow_nil: true`

**Step 5: Write tests for new model behavior**

Create `spec/models/completion_kit/metric_key_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::Metric, "key generation" do
  it "auto-generates key from name" do
    metric = create(:completion_kit_metric, name: "Relevance & Completeness")
    expect(metric.key).to eq("relevance-completeness")
  end

  it "does not overwrite an existing key" do
    metric = create(:completion_kit_metric, name: "Relevance", key: "custom_key")
    expect(metric.key).to eq("custom_key")
  end

  it "enforces uniqueness on key" do
    create(:completion_kit_metric, name: "Relevance", key: "relevance")
    duplicate = build(:completion_kit_metric, name: "Other", key: "relevance")
    expect(duplicate).not_to be_valid
  end
end
```

**Step 6: Run tests to verify**

Run: `bundle exec rspec spec/models/completion_kit/metric_key_spec.rb -v`
Expected: PASS

**Step 7: Commit**

```
feat: add key to metrics and source/eval_name to test_runs
```

---

### Task 2: EvalDefinition class

**Files:**
- Create: `lib/completion_kit/eval_definition.rb`
- Test: `spec/lib/completion_kit/eval_definition_spec.rb`

**Step 1: Write the failing test**

```ruby
require "rails_helper"

RSpec.describe CompletionKit::EvalDefinition do
  it "stores prompt name, dataset path, judge model, and metrics with thresholds" do
    defn = CompletionKit::EvalDefinition.new("support_summary")
    defn.prompt "support_summary"
    defn.dataset "evals/fixtures/support.csv"
    defn.judge_model "gpt-4.1"
    defn.metric :relevance, threshold: 7.0
    defn.metric :accuracy, threshold: 8.0

    expect(defn.eval_name).to eq("support_summary")
    expect(defn.prompt_name).to eq("support_summary")
    expect(defn.dataset_path).to eq("evals/fixtures/support.csv")
    expect(defn.judge_model_name).to eq("gpt-4.1")
    expect(defn.metrics).to eq([
      { key: :relevance, threshold: 7.0 },
      { key: :accuracy, threshold: 8.0 }
    ])
  end

  it "defaults judge_model from config" do
    defn = CompletionKit::EvalDefinition.new("test")
    defn.prompt "test"
    defn.dataset "test.csv"

    expect(defn.judge_model_name).to eq(CompletionKit.config.judge_model)
  end

  it "validates required fields" do
    defn = CompletionKit::EvalDefinition.new("incomplete")
    errors = defn.validation_errors

    expect(errors).to include(/prompt/)
    expect(errors).to include(/dataset/)
    expect(errors).to include(/metric/)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit/eval_definition_spec.rb -v`
Expected: FAIL — `uninitialized constant CompletionKit::EvalDefinition`

**Step 3: Write the implementation**

```ruby
module CompletionKit
  class EvalDefinition
    attr_reader :eval_name, :prompt_name, :dataset_path, :judge_model_name, :metrics

    def initialize(name)
      @eval_name = name
      @prompt_name = nil
      @dataset_path = nil
      @judge_model_name = nil
      @metrics = []
    end

    def prompt(name)
      @prompt_name = name
    end

    def dataset(path)
      @dataset_path = path
    end

    def judge_model(model)
      @judge_model_name = model
    end

    def metric(key, threshold:)
      @metrics << { key: key, threshold: threshold }
    end

    def resolved_judge_model
      @judge_model_name || CompletionKit.config.judge_model
    end

    def validation_errors
      errors = []
      errors << "No prompt specified" unless @prompt_name
      errors << "No dataset specified" unless @dataset_path
      errors << "No metrics specified" if @metrics.empty?
      errors
    end

    def valid?
      validation_errors.empty?
    end
  end
end
```

**Step 4: Update the `judge_model_name` reader to use resolved value**

The `judge_model_name` method should return `resolved_judge_model` so tests pass. Update the reader:

Replace `attr_reader :eval_name, :prompt_name, :dataset_path, :judge_model_name, :metrics` — keep `judge_model_name` as a custom method:

```ruby
attr_reader :eval_name, :prompt_name, :dataset_path, :metrics

def judge_model_name
  @judge_model_name || CompletionKit.config.judge_model
end
```

Remove the separate `resolved_judge_model` method — `judge_model_name` handles it.

**Step 5: Require from lib/completion_kit.rb**

Add `require "completion_kit/eval_definition"` in `lib/completion_kit.rb`.

**Step 6: Run tests**

Run: `bundle exec rspec spec/lib/completion_kit/eval_definition_spec.rb -v`
Expected: PASS

**Step 7: Commit**

```
feat: add EvalDefinition class
```

---

### Task 3: Eval registry and define_eval DSL

**Files:**
- Modify: `lib/completion_kit.rb`
- Test: `spec/lib/completion_kit/eval_registry_spec.rb`

**Step 1: Write the failing test**

```ruby
require "rails_helper"

RSpec.describe "CompletionKit.define_eval" do
  after { CompletionKit.clear_evals! }

  it "registers an eval definition" do
    CompletionKit.define_eval("my_eval") do |e|
      e.prompt "my_prompt"
      e.dataset "test.csv"
      e.metric :relevance, threshold: 7.0
    end

    expect(CompletionKit.registered_evals.size).to eq(1)
    expect(CompletionKit.registered_evals.first.eval_name).to eq("my_eval")
  end

  it "registers multiple evals" do
    CompletionKit.define_eval("eval_a") do |e|
      e.prompt "a"
      e.dataset "a.csv"
      e.metric :relevance, threshold: 7.0
    end

    CompletionKit.define_eval("eval_b") do |e|
      e.prompt "b"
      e.dataset "b.csv"
      e.metric :accuracy, threshold: 8.0
    end

    expect(CompletionKit.registered_evals.size).to eq(2)
  end

  it "clears the registry" do
    CompletionKit.define_eval("temp") do |e|
      e.prompt "temp"
      e.dataset "temp.csv"
      e.metric :x, threshold: 5.0
    end

    CompletionKit.clear_evals!
    expect(CompletionKit.registered_evals).to be_empty
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit/eval_registry_spec.rb -v`
Expected: FAIL — `undefined method 'define_eval'`

**Step 3: Add registry methods to CompletionKit module**

In `lib/completion_kit.rb`, add:

```ruby
def self.registered_evals
  @registered_evals ||= []
end

def self.define_eval(name, &block)
  defn = EvalDefinition.new(name)
  block.call(defn)
  registered_evals << defn
end

def self.clear_evals!
  @registered_evals = []
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/lib/completion_kit/eval_registry_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```
feat: add eval registry and define_eval DSL
```

---

### Task 4: EvalRunner

**Files:**
- Create: `lib/completion_kit/eval_runner.rb`
- Test: `spec/lib/completion_kit/eval_runner_spec.rb`

**Step 1: Write the failing test**

This is the big one. The runner needs to:
1. Look up the prompt by name
2. Read the CSV file
3. Create a test run with `source: "eval_dsl"`
4. Generate outputs via `test_run.run_tests`
5. Evaluate via `test_run.evaluate_results`
6. Compute per-metric averages
7. Compare against thresholds
8. Return structured results

```ruby
require "rails_helper"

RSpec.describe CompletionKit::EvalRunner do
  let!(:metric_group) { create(:completion_kit_metric_group) }
  let!(:relevance_metric) { create(:completion_kit_metric, name: "Relevance", key: "relevance", metric_groups: [metric_group]) }
  let!(:prompt) { create(:completion_kit_prompt, name: "test_prompt", metric_group: metric_group) }

  let(:csv_path) { Rails.root.join("tmp/test_eval.csv").to_s }
  let(:eval_defn) do
    defn = CompletionKit::EvalDefinition.new("test_eval")
    defn.prompt "test_prompt"
    defn.dataset csv_path
    defn.metric :relevance, threshold: 7.0
    defn
  end

  before do
    File.write(csv_path, "content\nhello\nworld\n")

    allow_any_instance_of(CompletionKit::LlmClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:configuration_errors).and_return([])
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:generate_completion).and_return("output text")
    allow_any_instance_of(CompletionKit::JudgeService).to receive(:evaluate).and_return({ score: 8.0, feedback: "Good" })
  end

  after { File.delete(csv_path) if File.exist?(csv_path) }

  describe "#run" do
    it "creates a test run, generates outputs, evaluates, and returns results" do
      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:eval_name]).to eq("test_eval")
      expect(result[:passed]).to be true
      expect(result[:metrics].first[:key]).to eq(:relevance)
      expect(result[:metrics].first[:average]).to be_a(Float)
      expect(result[:metrics].first[:threshold]).to eq(7.0)
      expect(result[:metrics].first[:passed]).to be true
      expect(result[:row_count]).to eq(2)
    end

    it "returns passed false when average is below threshold" do
      allow_any_instance_of(CompletionKit::JudgeService).to receive(:evaluate).and_return({ score: 3.0, feedback: "Poor" })

      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:passed]).to be false
      expect(result[:metrics].first[:passed]).to be false
    end

    it "stores the test run with source eval_dsl" do
      runner = described_class.new(eval_defn)
      runner.run

      test_run = CompletionKit::TestRun.last
      expect(test_run.source).to eq("eval_dsl")
      expect(test_run.eval_name).to eq("test_eval")
    end
  end

  describe "#run with missing prompt" do
    it "returns an error result" do
      eval_defn.prompt "nonexistent"
      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:passed]).to be false
      expect(result[:error]).to include("nonexistent")
    end
  end

  describe "#run with missing dataset file" do
    it "returns an error result" do
      File.delete(csv_path)
      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:passed]).to be false
      expect(result[:error]).to include("not found")
    end
  end

  describe "#run with unknown metric key" do
    it "returns an error result" do
      eval_defn.metric :nonexistent, threshold: 5.0
      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:passed]).to be false
      expect(result[:error]).to include("nonexistent")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit/eval_runner_spec.rb -v`
Expected: FAIL — `uninitialized constant CompletionKit::EvalRunner`

**Step 3: Write the implementation**

```ruby
module CompletionKit
  class EvalRunner
    attr_reader :eval_definition, :test_run

    def initialize(eval_definition)
      @eval_definition = eval_definition
    end

    def run
      prompt = resolve_prompt
      return error_result("Prompt '#{eval_definition.prompt_name}' not found") unless prompt

      return error_result("Dataset '#{eval_definition.dataset_path}' not found") unless File.exist?(eval_definition.dataset_path)

      csv_data = File.read(eval_definition.dataset_path)

      metric_keys = eval_definition.metrics.map { |m| m[:key] }
      available_metrics = Metric.where(key: metric_keys.map(&:to_s)).index_by(&:key)
      missing = metric_keys.select { |k| available_metrics[k.to_s].nil? }
      if missing.any?
        available = Metric.pluck(:key).compact.join(", ")
        return error_result("Unknown metric keys: #{missing.join(", ")}. Available: #{available}")
      end

      @test_run = TestRun.create!(
        prompt: prompt,
        name: "eval: #{eval_definition.eval_name} (#{Time.current.strftime("%Y-%m-%d %H:%M")})",
        csv_data: csv_data,
        source: "eval_dsl",
        eval_name: eval_definition.eval_name
      )

      @test_run.run_tests
      @test_run.evaluate_results

      row_count = @test_run.test_results.count
      metric_results = eval_definition.metrics.map do |metric_def|
        assessments = TestResultMetricAssessment.joins(:test_result)
          .where(test_results: { test_run_id: @test_run.id })
          .where(metric_key_or_name_clause(metric_def[:key]))

        scores = assessments.where.not(ai_score: nil).pluck(:ai_score)
        average = scores.any? ? (scores.sum / scores.size).round(2) : 0.0

        {
          key: metric_def[:key],
          threshold: metric_def[:threshold],
          average: average,
          passed: average >= metric_def[:threshold]
        }
      end

      {
        eval_name: eval_definition.eval_name,
        row_count: row_count,
        metrics: metric_results,
        passed: metric_results.all? { |m| m[:passed] },
        test_run_id: @test_run.id
      }
    rescue StandardError => e
      error_result(e.message)
    end

    private

    def resolve_prompt
      Prompt.current_for(eval_definition.prompt_name)
    end

    def metric_key_or_name_clause(key)
      metric = Metric.find_by(key: key.to_s)
      return { metric_id: metric.id } if metric

      { metric_name: key.to_s }
    end

    def error_result(message)
      {
        eval_name: eval_definition.eval_name,
        row_count: 0,
        metrics: [],
        passed: false,
        error: message
      }
    end
  end
end
```

**Step 4: Require from lib/completion_kit.rb**

Add `require "completion_kit/eval_runner"`.

**Step 5: Run tests**

Run: `bundle exec rspec spec/lib/completion_kit/eval_runner_spec.rb -v`
Expected: PASS

**Step 6: Commit**

```
feat: add EvalRunner to execute eval definitions
```

---

### Task 5: EvalFormatter — terminal output

**Files:**
- Create: `lib/completion_kit/eval_formatter.rb`
- Test: `spec/lib/completion_kit/eval_formatter_spec.rb`

**Step 1: Write the failing test**

```ruby
require "rails_helper"

RSpec.describe CompletionKit::EvalFormatter do
  describe ".format_results" do
    it "formats passing results" do
      results = [
        {
          eval_name: "support_summary",
          row_count: 24,
          metrics: [
            { key: :relevance, average: 8.2, threshold: 7.0, passed: true },
            { key: :accuracy, average: 8.7, threshold: 8.0, passed: true }
          ],
          passed: true
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("support_summary")
      expect(output).to include("24 rows")
      expect(output).to include("relevance")
      expect(output).to include("8.2")
      expect(output).to include("pass")
      expect(output).to include("2 passed, 0 failed")
    end

    it "formats failing results" do
      results = [
        {
          eval_name: "translation",
          row_count: 7,
          metrics: [
            { key: :relevance, average: 6.8, threshold: 7.0, passed: false },
            { key: :fluency, average: 9.1, threshold: 8.0, passed: true }
          ],
          passed: false
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("FAIL")
      expect(output).to include("0 passed, 1 failed")
      expect(output).to include("relevance")
      expect(output).to include("6.8")
    end

    it "formats error results" do
      results = [
        {
          eval_name: "broken",
          row_count: 0,
          metrics: [],
          passed: false,
          error: "Prompt 'missing' not found"
        }
      ]

      output = described_class.format_results(results)

      expect(output).to include("ERROR")
      expect(output).to include("missing")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit/eval_formatter_spec.rb -v`
Expected: FAIL

**Step 3: Write the implementation**

```ruby
module CompletionKit
  class EvalFormatter
    def self.format_results(results)
      lines = ["\nCompletionKit Evals\n"]

      results.each do |result|
        if result[:error]
          lines << "  #{result[:eval_name]}  ERROR: #{result[:error]}"
          lines << ""
          next
        end

        lines << "  #{result[:eval_name]}  #{result[:row_count]} rows"

        result[:metrics].each do |m|
          status = m[:passed] ? "pass" : "FAIL"
          lines << "    %-20s avg %-6s (threshold %-4s) %s" % [
            m[:key], m[:average], m[:threshold], status
          ]
        end

        lines << ""
      end

      passed = results.count { |r| r[:passed] }
      failed = results.count { |r| !r[:passed] }
      lines << "#{passed} passed, #{failed} failed"

      failures = results.reject { |r| r[:passed] }
      failures.each do |result|
        if result[:error]
          lines << "Failed: #{result[:eval_name]} — #{result[:error]}"
        else
          result[:metrics].reject { |m| m[:passed] }.each do |m|
            lines << "Failed: #{result[:eval_name]} — #{m[:key]} scored #{m[:average]}, threshold #{m[:threshold]}"
          end
        end
      end

      lines.join("\n") + "\n"
    end
  end
end
```

**Step 4: Require from lib/completion_kit.rb**

Add `require "completion_kit/eval_formatter"`.

**Step 5: Run tests**

Run: `bundle exec rspec spec/lib/completion_kit/eval_formatter_spec.rb -v`
Expected: PASS

**Step 6: Commit**

```
feat: add EvalFormatter for terminal output
```

---

### Task 6: Rake tasks

**Files:**
- Modify: `lib/tasks/completion_kit_tasks.rake`
- Test: `spec/lib/tasks/eval_rake_spec.rb`

**Step 1: Write the failing test**

```ruby
require "rails_helper"
require "rake"

RSpec.describe "completion_kit:eval rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  describe "completion_kit:metrics" do
    it "lists available metrics" do
      create(:completion_kit_metric, name: "Relevance", key: "relevance")

      expect { Rake::Task["completion_kit:metrics"].execute }.to output(/relevance/).to_stdout
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/tasks/eval_rake_spec.rb -v`
Expected: FAIL

**Step 3: Write the rake tasks**

In `lib/tasks/completion_kit_tasks.rake`:

```ruby
namespace :completion_kit do
  desc "Run all prompt evals in evals/ directory"
  task eval: :environment do
    eval_files = Dir[Rails.root.join("evals/**/*_eval.rb")]

    if eval_files.empty?
      puts "No eval files found in evals/. Create evals/*_eval.rb files."
      exit 0
    end

    CompletionKit.clear_evals!
    eval_files.each { |f| load f }

    if CompletionKit.registered_evals.empty?
      puts "No evals registered. Use CompletionKit.define_eval in your eval files."
      exit 0
    end

    results = CompletionKit.registered_evals.map do |defn|
      errors = defn.validation_errors
      if errors.any?
        { eval_name: defn.eval_name, row_count: 0, metrics: [], passed: false, error: errors.join(", ") }
      else
        runner = CompletionKit::EvalRunner.new(defn)
        runner.run
      end
    end

    puts CompletionKit::EvalFormatter.format_results(results)

    exit 1 if results.any? { |r| !r[:passed] }
  end

  namespace :eval do
    desc "Dry run: validate eval definitions without calling APIs"
    task dry_run: :environment do
      eval_files = Dir[Rails.root.join("evals/**/*_eval.rb")]

      if eval_files.empty?
        puts "No eval files found in evals/."
        exit 0
      end

      CompletionKit.clear_evals!
      eval_files.each { |f| load f }

      puts "\nCompletionKit Eval Dry Run\n\n"

      all_valid = true
      CompletionKit.registered_evals.each do |defn|
        errors = defn.validation_errors

        prompt = CompletionKit::Prompt.current_for(defn.prompt_name) if defn.prompt_name
        errors << "Prompt '#{defn.prompt_name}' not found" if defn.prompt_name && !prompt
        errors << "Dataset '#{defn.dataset_path}' not found" if defn.dataset_path && !File.exist?(defn.dataset_path)

        defn.metrics.each do |m|
          unless CompletionKit::Metric.exists?(key: m[:key].to_s)
            errors << "Unknown metric key: #{m[:key]}"
          end
        end

        if errors.any?
          all_valid = false
          puts "  #{defn.eval_name}  INVALID"
          errors.each { |e| puts "    - #{e}" }
        else
          row_count = File.readlines(defn.dataset_path).size - 1
          puts "  #{defn.eval_name}  OK (#{row_count} rows, #{defn.metrics.size} metrics)"
        end
        puts ""
      end

      exit 1 unless all_valid
    end
  end

  desc "List available metrics and their keys"
  task metrics: :environment do
    metrics = CompletionKit::Metric.order(:name)

    if metrics.empty?
      puts "No metrics defined yet."
      exit 0
    end

    puts "\nAvailable metrics:\n\n"
    metrics.each do |m|
      puts "  %-25s key: %s" % [m.name, m.key || "(no key)"]
    end
    puts ""
  end
end
```

**Step 4: Run tests**

Run: `bundle exec rspec spec/lib/tasks/eval_rake_spec.rb -v`
Expected: PASS

**Step 5: Commit**

```
feat: add rake tasks for eval runner, dry run, and metrics listing
```

---

### Task 7: UI — show source chip on test runs

**Files:**
- Modify: `app/views/completion_kit/test_runs/index.html.erb`
- Modify: `app/views/completion_kit/test_runs/show.html.erb`

**Step 1: Add source chip to test runs index**

In the inline div that shows the run name and status badge, add after the status badge:

```erb
<% if test_run.respond_to?(:source) && test_run.source == "eval_dsl" %>
  <span class="ck-chip ck-chip--soft">eval</span>
<% end %>
```

**Step 2: Add source chip to test run show page**

In the inline div with the title and status badge, add the same chip.

**Step 3: Verify visually**

Boot the demo app and confirm the chip renders on eval-sourced runs.

**Step 4: Commit**

```
feat: show eval source chip on test run pages
```

---

### Task 8: Full integration test

**Files:**
- Create: `spec/lib/completion_kit/eval_integration_spec.rb`

**Step 1: Write the integration test**

```ruby
require "rails_helper"

RSpec.describe "Eval DSL end-to-end" do
  let!(:metric_group) { create(:completion_kit_metric_group) }
  let!(:relevance) { create(:completion_kit_metric, name: "Relevance", key: "relevance", metric_groups: [metric_group]) }
  let!(:accuracy) { create(:completion_kit_metric, name: "Accuracy", key: "accuracy", metric_groups: [metric_group]) }
  let!(:prompt) { create(:completion_kit_prompt, name: "e2e_test", metric_group: metric_group, current: true) }

  let(:csv_path) { Rails.root.join("tmp/e2e_eval.csv").to_s }

  before do
    File.write(csv_path, "content\nfirst row\nsecond row\n")
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:configured?).and_return(true)
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:configuration_errors).and_return([])
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:generate_completion).and_return("generated output")
    allow_any_instance_of(CompletionKit::JudgeService).to receive(:evaluate).and_return({ score: 8.5, feedback: "Good work" })
  end

  after do
    CompletionKit.clear_evals!
    File.delete(csv_path) if File.exist?(csv_path)
  end

  it "defines an eval, runs it, and gets structured results" do
    CompletionKit.define_eval("e2e_test") do |e|
      e.prompt "e2e_test"
      e.dataset csv_path
      e.metric :relevance, threshold: 7.0
      e.metric :accuracy, threshold: 8.0
    end

    defn = CompletionKit.registered_evals.first
    runner = CompletionKit::EvalRunner.new(defn)
    result = runner.run

    expect(result[:passed]).to be true
    expect(result[:row_count]).to eq(2)
    expect(result[:metrics].size).to eq(2)

    test_run = CompletionKit::TestRun.find(result[:test_run_id])
    expect(test_run.source).to eq("eval_dsl")
    expect(test_run.eval_name).to eq("e2e_test")

    output = CompletionKit::EvalFormatter.format_results([result])
    expect(output).to include("2 rows")
    expect(output).to include("pass")
    expect(output).to include("1 passed, 0 failed")
  end
end
```

**Step 2: Run test**

Run: `bundle exec rspec spec/lib/completion_kit/eval_integration_spec.rb -v`
Expected: PASS

**Step 3: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass, 100% coverage

**Step 4: Commit**

```
feat: add eval DSL integration test
```

---

### Task 9: Update install generator

**Files:**
- Modify: `lib/generators/completion_kit/install_generator.rb`

**Step 1: Add eval directory creation to the generator**

The install generator should create the `evals/` directory and an example eval file so users have a starting point.

Add to the generator:

```ruby
def create_eval_directory
  empty_directory "evals/fixtures"
  create_file "evals/example_eval.rb", <<~RUBY
    CompletionKit.define_eval("example") do |e|
      e.prompt "your_prompt_name"
      e.dataset "evals/fixtures/example.csv"
      e.judge_model "gpt-4.1"

      e.metric :relevance, threshold: 7.0
    end
  RUBY
end
```

**Step 2: Commit**

```
feat: add eval directory scaffold to install generator
```

---

### Task 10: Final pass — run full suite, verify coverage

**Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass, 100% line and branch coverage

**Step 2: Fix any coverage gaps**

If coverage drops below 100%, add tests for uncovered branches.

**Step 3: Commit any fixes**

```
test: ensure 100% coverage for eval DSL
```
