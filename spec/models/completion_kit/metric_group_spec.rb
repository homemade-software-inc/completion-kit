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

  describe "#replace_metrics!" do
    let(:metric) { create(:completion_kit_metric) }
    let(:group) { create(:completion_kit_metric_group) }

    before { group.replace_metrics!([metric.id]) }

    it "leaves the members alone when given nil" do
      group.replace_metrics!(nil)

      expect(group.metric_group_memberships.pluck(:metric_id)).to eq([metric.id])
    end

    it "attaches a repeated id once" do
      other = create(:completion_kit_metric)

      group.replace_metrics!([other.id, other.id.to_s, "", metric.id, other.id])

      expect(group.metric_group_memberships.pluck(:metric_id, :position)).to eq([[other.id, 1], [metric.id, 2]])
    end

    it "clears the members when given an empty list" do
      group.replace_metrics!([])

      expect(group.metric_group_memberships).to be_empty
    end
  end

  describe "#selected_metric_ids" do
    let(:metric) { create(:completion_kit_metric) }
    let(:other) { create(:completion_kit_metric) }
    let(:group) { create(:completion_kit_metric_group) }

    before { group.replace_metrics!([metric.id]) }

    it "reads the saved members when no selection is assigned" do
      expect(group.selected_metric_ids).to eq([metric.id])
    end

    it "keeps the pending selection after a failed save" do
      expect(group.update(name: "", selected_metric_ids: ["", other.id.to_s])).to be(false)

      expect(group.selected_metric_ids).to eq([other.id])
      expect(group.metric_group_memberships.pluck(:metric_id)).to eq([metric.id])
    end
  end

  describe "metric ids outside the tenant scope" do
    let(:own_metric) { create(:completion_kit_metric, name: "Own") }
    let!(:foreign_metric) { create(:completion_kit_metric, name: "Foreign") }

    before { hide_outside_tenant(foreign_metric) }

    it "rejects another tenant's metric before writing the group" do
      group = described_class.new(name: "Cross", selected_metric_ids: [own_metric.id, foreign_metric.id])

      expect(group.save).to be(false)
      expect(group.errors.full_messages).to eq(["Metrics include one that isn't available"])
      expect(described_class.unscoped.count).to eq(0)
      expect(CompletionKit::MetricGroupMembership.unscoped.count).to eq(0)
    end

    it "keeps the existing members when an update points at another tenant's metric" do
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([own_metric.id])

      expect(group.update(selected_metric_ids: [foreign_metric.id])).to be(false)
      expect(group.reload.metric_group_memberships.pluck(:metric_id)).to eq([own_metric.id])
    end

    it "attaches the selected metrics once the group saves" do
      group = described_class.create!(name: "Mine", selected_metric_ids: [own_metric.id])

      expect(group.metric_group_memberships.pluck(:metric_id, :position)).to eq([[own_metric.id, 1]])
    end

    it "refuses a membership on a metric the tenant cannot see" do
      membership = CompletionKit::MetricGroupMembership.new(metric_group: create(:completion_kit_metric_group), metric_id: foreign_metric.id)

      expect(membership).not_to be_valid
      expect(membership.errors.full_messages).to eq(["Metric must exist"])
    end
  end

  it "assigns a default position when one is not provided" do
    metric_group = create(:completion_kit_metric_group)
    membership = create(:completion_kit_metric_group_membership, metric_group: metric_group, position: nil)

    expect(membership.position).to eq(1)
  end
end
