require "rails_helper"

RSpec.describe CompletionKit::MetricGroup, type: :model do
  describe "destroy cascade" do
    it "destroys memberships but keeps member metrics" do
      group = create(:completion_kit_metric_group)
      metric = create(:completion_kit_metric)
      create(:completion_kit_metric_group_membership, metric_group: group, metric: metric)

      expect { group.destroy! }
        .to change(CompletionKit::MetricGroupMembership, :count).by(-1)
        .and change(CompletionKit::Metric, :count).by(0)

      expect(CompletionKit::Metric.exists?(metric.id)).to be(true)
    end
  end

  it "orders metrics by membership position" do
    metric_group = create(:completion_kit_metric_group)
    later_metric = create(:completion_kit_metric, name: "Later")
    earlier_metric = create(:completion_kit_metric, name: "Earlier")
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: later_metric, position: 2)
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: earlier_metric, position: 1)

    expect(metric_group.ordered_metrics).to eq([earlier_metric, later_metric])
  end

  it "assigns a default position when one is not provided" do
    metric_group = create(:completion_kit_metric_group)
    membership = create(:completion_kit_metric_group_membership, metric_group: metric_group, position: nil)

    expect(membership.position).to eq(1)
  end
end
