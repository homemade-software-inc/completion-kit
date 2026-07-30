require "rails_helper"

RSpec.describe CompletionKit::StartRunJob, type: :job do
  let(:prompt) { create(:completion_kit_prompt, template: "Static prompt") }
  let(:run) { create(:completion_kit_run, prompt: prompt, dataset: nil) }

  before do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true, configuration_errors: [])
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
  end

  it "inserts the rows and enqueues the row jobs the claimed run is waiting for" do
    run.start!
    expect(run.reload.responses.count).to eq(0)

    described_class.perform_now(run.id)

    expect(run.reload.responses.count).to eq(1)
    expect(run.progress_total).to eq(1)
  end

  it "does nothing when the run has been deleted" do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end

  it "does nothing for a run that is no longer running" do
    run.update_columns(status: "completed")

    described_class.perform_now(run.id)

    expect(run.reload.responses.count).to eq(0)
  end

  it "does not insert a second time if the job is retried after the rows landed" do
    run.start!
    described_class.perform_now(run.id)

    expect { described_class.perform_now(run.id) }.not_to change { run.reload.responses.count }
  end

  it "fails the run with the error when the heavy work raises" do
    run.start!
    allow_any_instance_of(CompletionKit::Run).to receive(:execute_start!).and_raise(StandardError, "csv exploded")
    allow(Rails.error).to receive(:report)

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("failed")
    expect(run.failure_summary).to eq("csv exploded")
  end

  it "reports the error and stops when the run is deleted mid-flight" do
    run.start!
    allow_any_instance_of(CompletionKit::Run).to receive(:execute_start!).and_raise(StandardError, "boom")
    allow(CompletionKit::Run).to receive(:find_by).and_return(run, nil)
    allow(Rails.error).to receive(:report)

    expect { described_class.perform_now(run.id) }.not_to raise_error
  end

  it "fails the run when the dataset lost its rows between the claim and the insert" do
    dataset_run = create(:completion_kit_run, prompt: prompt, dataset: create(:completion_kit_dataset))
    expect(dataset_run.start!).to be(true)
    allow(CompletionKit::CsvProcessor).to receive(:process_self).and_return([])

    expect(dataset_run.execute_start!).to be(false)

    expect(dataset_run.reload.status).to eq("failed")
    expect(dataset_run.failure_summary).to eq("Dataset has no rows")
  end

  it "concurrency key serializes starts per run" do
    key_proc = described_class.concurrency_key
    expect(key_proc.call(run.id)).to eq("run:#{run.id}:start")
  end
end
