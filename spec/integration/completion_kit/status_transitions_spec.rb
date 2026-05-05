require "rails_helper"

RSpec.describe "Run status transitions", type: :model do
  let(:prompt) { create(:completion_kit_prompt, llm_model: "gpt-4.1") }
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

  it "pending -> running after start!" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No judge")

    run.start!
    expect(run.reload.status).to eq("running")
  end

  it "sets status to failed when dataset has no rows" do
    dataset = create(:completion_kit_dataset, csv_data: "header\n")
    allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])
    run = CompletionKit::Run.create!(prompt: prompt, dataset: dataset, name: "Empty dataset")

    result = run.start!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end

  it "sets status to failed when LLM client is not configured" do
    bad_client = instance_double(CompletionKit::LlmClient, configured?: false, configuration_errors: ["missing key"])
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(bad_client)
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "Bad config")

    result = run.start!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end

  it "transitions to completed via mark_completed!" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "Complete me", status: "running")

    run.mark_completed!
    expect(run.reload.status).to eq("completed")
  end
end
