require "rails_helper"

RSpec.describe CompletionKit::EvalRunner do
  let!(:metric_group) { create(:completion_kit_metric_group) }
  let!(:relevance_metric) { create(:completion_kit_metric, name: "Relevance", key: "relevance") }
  let!(:membership) { create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: relevance_metric) }
  let!(:prompt) do
    create(:completion_kit_prompt,
      name: "test_prompt",
      template: "Summarize {{content}} for {{audience}}",
      metric_group: metric_group)
  end

  let(:csv_path) { Rails.root.join("tmp/test_eval.csv").to_s }
  let(:eval_defn) do
    defn = CompletionKit::EvalDefinition.new("test_eval")
    defn.prompt "test_prompt"
    defn.dataset csv_path
    defn.metric :relevance, threshold: 7.0
    defn
  end

  before do
    FileUtils.mkdir_p(File.dirname(csv_path))
    File.write(csv_path, "content,audience,expected_output\nhello,devs,summary1\nworld,managers,summary2\n")

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
      expect(result[:error]).to be_nil
      expect(result[:metrics]).not_to be_empty, "Expected metrics but got: #{result.inspect}"
      expect(result[:metrics].first[:average]).to be >= 7.0, "Average #{result[:metrics].first[:average]} below threshold. Assessments: #{CompletionKit::TestResultMetricAssessment.count}, TestResults: #{CompletionKit::TestResult.count}"
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

  describe "#run with no scores" do
    it "returns 0.0 average when judge returns no scores" do
      allow_any_instance_of(CompletionKit::JudgeService).to receive(:evaluate).and_return({ score: nil, feedback: "Error" })

      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:metrics].first[:average]).to eq(0.0)
      expect(result[:metrics].first[:passed]).to be false
    end
  end

  describe "#run with unexpected error" do
    it "returns an error result" do
      allow(CompletionKit::TestRun).to receive(:create!).and_raise(StandardError, "boom")

      runner = described_class.new(eval_defn)
      result = runner.run

      expect(result[:passed]).to be false
      expect(result[:error]).to eq("boom")
    end
  end

end
