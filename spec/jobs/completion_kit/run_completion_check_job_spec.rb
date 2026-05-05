require "rails_helper"

RSpec.describe CompletionKit::RunCompletionCheckJob, type: :job do
  let(:run) { create(:completion_kit_run, status: "running") }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
  end

  it "transitions a running run with no outstanding work to completed" do
    allow_any_instance_of(CompletionKit::Run).to receive(:outstanding_work_zero?).and_return(true)
    allow_any_instance_of(CompletionKit::Run).to receive(:mark_completed!).and_call_original

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("completed")
  end

  it "leaves the run as running when work is outstanding" do
    allow_any_instance_of(CompletionKit::Run).to receive(:outstanding_work_zero?).and_return(false)
    expect_any_instance_of(CompletionKit::Run).not_to receive(:mark_completed!)

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("running")
  end

  it "is a no-op when the run is already completed" do
    run.update!(status: "completed")
    expect_any_instance_of(CompletionKit::Run).not_to receive(:outstanding_work_zero?)
    expect_any_instance_of(CompletionKit::Run).not_to receive(:mark_completed!)

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("completed")
  end

  it "is a no-op when the run does not exist" do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end

  it "concurrency key serializes completion checks per run" do
    key_proc = described_class.concurrency_key
    expect(key_proc.call(run.id)).to eq("run:#{run.id}:completion")
  end
end
