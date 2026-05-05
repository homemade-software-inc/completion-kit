require "rails_helper"

RSpec.describe CompletionKit::JudgeJob, type: :job do
  it "performs without error" do
    run = create(:completion_kit_run)
    expect { described_class.perform_now(run.id) }.not_to raise_error
  end

  it "handles missing run gracefully" do
    expect { described_class.perform_now(999999) }.not_to raise_error
  end
end
