require "rails_helper"

RSpec.describe CompletionKit::DashboardDismissal, type: :model do
  it "is valid pointing at a metric with a baseline score" do
    dismissal = described_class.new(dismissable: create(:completion_kit_metric), baseline_score: 3.2)
    expect(dismissal).to be_valid
  end

  it "is valid pointing at a failed run with no baseline score" do
    dismissal = described_class.new(dismissable: create(:completion_kit_run))
    expect(dismissal).to be_valid
  end

  it "rejects an unsupported dismissable type" do
    dismissal = described_class.new(dismissable: create(:completion_kit_dataset))
    expect(dismissal).not_to be_valid
    expect(dismissal.errors[:dismissable_type]).to be_present
  end

  it "rejects a duplicate dismissal of the same record" do
    metric = create(:completion_kit_metric)
    described_class.create!(dismissable: metric)
    dup = described_class.new(dismissable: metric)
    expect(dup).not_to be_valid
  end

  it "scopes metric dismissals and failure dismissals apart" do
    metric_d = described_class.create!(dismissable: create(:completion_kit_metric))
    run_d = described_class.create!(dismissable: create(:completion_kit_run))

    expect(described_class.metrics).to contain_exactly(metric_d)
    expect(described_class.failures).to contain_exactly(run_d)
  end

  it "is destroyed when its dismissable is destroyed" do
    run = create(:completion_kit_run)
    described_class.create!(dismissable: run)
    expect { run.destroy }.to change(described_class, :count).by(-1)
  end
end
