require "rails_helper"

RSpec.describe CompletionKit::JudgeJob, type: :job do
  it "calls judge_responses! on the run" do
    run = create(:completion_kit_run)
    allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!).and_return(true)
    described_class.perform_now(run.id)
  end

  it "handles missing run gracefully" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end
end
