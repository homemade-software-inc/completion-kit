require "rails_helper"

RSpec.describe "End-to-end generation pipeline", type: :model do
  let(:prompt) do
    create(:completion_kit_prompt,
      name: "Summarizer", template: "Summarize {{content}} for {{audience}}",
      llm_model: "gpt-4.1")
  end
  let(:client) { instance_double(CompletionKit::LlmClient, configured?: true, configuration_errors: []) }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
  end

  context "with a dataset" do
    let(:dataset) do
      create(:completion_kit_dataset, csv_data: <<~CSV)
        content,audience,expected_output
        "Release notes","developers","A developer-focused summary"
        "Company update","executives","An executive briefing"
      CSV
    end

    it "creates one pending response per row, transitions to running, enqueues jobs" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: dataset, name: "Pipeline test")

      expect(run.status).to eq("pending")
      result = run.start!

      expect(result).to be true
      expect(run.reload.status).to eq("running")
      expect(run.responses.count).to eq(2)
      expect(run.responses.pluck(:status).uniq).to eq(["pending"])
      expect(run.responses.pluck(:row_index)).to contain_exactly(0, 1)
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).twice
    end
  end

  context "without a dataset" do
    let(:prompt) { create(:completion_kit_prompt, name: "Static", template: "Run with no inputs", llm_model: "gpt-4.1") }

    it "creates a single pending response with nil input_data" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No dataset test")

      run.start!

      expect(run.reload.status).to eq("running")
      expect(run.responses.count).to eq(1)
      expect(run.responses.first.input_data).to be_nil
      expect(run.responses.first.status).to eq("pending")
    end
  end
end
