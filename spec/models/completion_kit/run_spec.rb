require "rails_helper"

RSpec.describe CompletionKit::Run, type: :model do
  describe "#metrics" do
    it "returns empty array when criteria is nil" do
      run = build(:completion_kit_run, criteria: nil)
      expect(run.metrics).to eq([])
    end
  end

  describe "#generate_responses!" do
    let(:prompt) { create(:completion_kit_prompt) }

    it "adds error and returns false when dataset has rows but they come back empty" do
      dataset = create(:completion_kit_dataset, csv_data: "header\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset)

      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

      result = run.generate_responses!

      expect(result).to be false
      expect(run.errors[:base]).to include("Dataset has no rows")
    end

    it "adds error but does not update_column when run is not persisted and LLM is unconfigured" do
      run = build(:completion_kit_run, prompt: prompt, dataset: nil)

      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

      client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      result = run.generate_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("LLM API not configured")
      expect(run).not_to be_persisted
    end

    it "adds error, marks failed, and returns false when LLM client is not configured" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

      client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["API key missing"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      result = run.generate_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("LLM API not configured")
      expect(run.reload.status).to eq("failed")
    end

    it "adds error and does not update_column when StandardError is raised on a non-persisted run" do
      run = build(:completion_kit_run, prompt: prompt, dataset: nil)

      allow(CompletionKit::CsvProcessor).to receive(:process_self).and_raise(StandardError, "boom")

      result = run.generate_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("boom")
      expect(run).not_to be_persisted
    end
  end

  describe "#judge_responses!" do
    let(:metric) { create(:completion_kit_metric, name: "Quality") }
    let(:criteria) do
      c = create(:completion_kit_criteria)
      CompletionKit::CriteriaMembership.create!(criteria: c, metric: metric, position: 1)
      c
    end
    let(:prompt) { create(:completion_kit_prompt) }

    it "marks status failed without update_column on non-persisted run error" do
      run = build(
        :completion_kit_run,
        prompt: prompt,
        judge_model: "gpt-4.1",
        criteria: criteria,
        status: "completed"
      )

      allow(run).to receive(:update!).and_raise(StandardError, "judge error")

      result = run.judge_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("judge error")
      expect(run).not_to be_persisted
    end

    it "calls respond_to? false branches via a minimal duck-typed metric" do
      minimal_metric = Struct.new(:id, :name).new(metric.id, "custom")
      run = create(
        :completion_kit_run,
        prompt: prompt,
        judge_model: "gpt-4.1",
        criteria: criteria,
        status: "completed"
      )
      run.responses.create!(response_text: "Some output")

      allow(run).to receive(:metrics).and_return([minimal_metric])

      judge = instance_double(CompletionKit::JudgeService, evaluate: { score: 4.0, feedback: "ok" })
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({ api_key: "x" })

      result = run.judge_responses!

      expect(result).to be true
      expect(run.reload.status).to eq("completed")
    end
  end
end
