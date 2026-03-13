require "rails_helper"

RSpec.describe CompletionKit::Criteria, type: :model do
  it "orders metrics by membership position" do
    criteria = create(:completion_kit_criteria)
    later_metric = create(:completion_kit_metric, name: "Later")
    earlier_metric = create(:completion_kit_metric, name: "Earlier")
    create(:completion_kit_criteria_membership, criteria: criteria, metric: later_metric, position: 2)
    create(:completion_kit_criteria_membership, criteria: criteria, metric: earlier_metric, position: 1)

    expect(criteria.ordered_metrics).to eq([earlier_metric, later_metric])
  end

  it "assigns a default position when one is not provided" do
    criteria = create(:completion_kit_criteria)
    membership = create(:completion_kit_criteria_membership, criteria: criteria, position: nil)

    expect(membership.position).to eq(1)
  end
end
