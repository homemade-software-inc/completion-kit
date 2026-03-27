require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::Run, type: :model do
  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
  end

  describe "#metrics" do
    it "returns empty array when criteria is nil" do
      run = build(:completion_kit_run, criteria: nil)
      expect(run.metrics).to eq([])
    end
  end

  describe "broadcast helpers" do
    let(:prompt) { create(:completion_kit_prompt) }
    let(:run) { create(:completion_kit_run, prompt: prompt) }

    before do
      allow(run).to receive(:broadcast_progress).and_call_original
      allow(run).to receive(:broadcast_response).and_call_original
      allow(run).to receive(:broadcast_response_update).and_call_original
      allow(run).to receive(:broadcast_replace_to)
      allow(run).to receive(:broadcast_append_to)
    end

    it "broadcast_progress calls broadcast_replace_to with run_progress target" do
      run.send(:broadcast_progress)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_progress")
      )
    end

    it "broadcast_response calls broadcast_append_to with run_responses target" do
      response = run.responses.create!(response_text: "test")
      run.send(:broadcast_response, response)
      expect(run).to have_received(:broadcast_append_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "run_responses")
      )
    end

    it "broadcast_response_update calls broadcast_replace_to with response target" do
      response = run.responses.create!(response_text: "test")
      run.send(:broadcast_response_update, response)
      expect(run).to have_received(:broadcast_replace_to).with(
        "completion_kit_run_#{run.id}",
        hash_including(target: "response_#{response.id}")
      )
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

    it "adds error and marks status failed when StandardError is raised during generation" do
      run = create(:completion_kit_run, prompt: prompt, dataset: nil)

      client = instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: [])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(client).to receive(:generate_completion).and_raise(StandardError, "boom")

      result = run.generate_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("boom")
      expect(run.reload.status).to eq("failed")
    end

    it "adds error without update_columns on non-persisted run when StandardError is raised at update!" do
      run = build(:completion_kit_run, prompt: prompt, dataset: nil)

      client = instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: [])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      allow(run).to receive(:update!).and_raise(StandardError, "boom")

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

    it "marks status failed with update_columns on persisted run when StandardError is raised during judging" do
      run = create(
        :completion_kit_run,
        prompt: prompt,
        judge_model: "gpt-4.1",
        criteria: criteria,
        status: "completed"
      )
      run.responses.create!(response_text: "Some output")

      allow(CompletionKit::JudgeService).to receive(:new).and_raise(StandardError, "judge boom")

      result = run.judge_responses!

      expect(result).to be false
      expect(run.errors[:base].first).to include("judge boom")
      expect(run.reload.status).to eq("failed")
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
