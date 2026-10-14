require "rails_helper"

RSpec.describe CompletionKit::McpTools::MetricGroups do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metric_groups_list metric_groups_get metric_groups_create metric_groups_update metric_groups_delete
      ])
    end
  end

  describe ".call" do
    let!(:metric_group) { create(:completion_kit_metric_group, name: "Quality") }

    it "lists metric groups" do
      result = described_class.call("metric_groups_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Quality")
    end

    it "gets a metric group by id" do
      result = described_class.call("metric_groups_get", {"id" => metric_group.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(metric_group.id)
    end

    it "creates a metric group" do
      result = described_class.call("metric_groups_create", {"name" => "New Group"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Group")
    end

    it "creates a metric group with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("metric_groups_create", {"name" => "With Metrics", "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "updates a metric group" do
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "updates a metric group with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    describe "with metrics from another tenant" do
      let(:own_metric) { create(:completion_kit_metric, name: "Own") }
      let!(:foreign_metric) { create(:completion_kit_metric, name: "Foreign") }

      before { hide_outside_tenant(foreign_metric) }

      it "refuses to create a group on another tenant's metric and writes nothing" do
        expect {
          result = described_class.call("metric_groups_create", {"name" => "Cross", "metric_ids" => [own_metric.id, foreign_metric.id]})
          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to eq("Metrics include one that isn't available")
        }.not_to change { [CompletionKit::MetricGroup.unscoped.count, CompletionKit::MetricGroupMembership.unscoped.count] }
      end

      it "refuses to swap a group's metrics for another tenant's and keeps the old ones" do
        metric_group.replace_metrics!([own_metric.id])

        result = described_class.call("metric_groups_update", {"id" => metric_group.id, "metric_ids" => [foreign_metric.id]})

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to eq("Metrics include one that isn't available")
        expect(metric_group.metric_group_memberships.pluck(:metric_id)).to eq([own_metric.id])
      end

      it "leaves a group's metrics alone when an update names none" do
        metric_group.replace_metrics!([own_metric.id])

        described_class.call("metric_groups_update", {"id" => metric_group.id, "name" => "Renamed"})

        expect(metric_group.metric_group_memberships.pluck(:metric_id)).to eq([own_metric.id])
      end
    end

    it "returns error on invalid create" do
      result = described_class.call("metric_groups_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("metric_groups_update", {"id" => metric_group.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a metric group" do
      result = described_class.call("metric_groups_delete", {"id" => metric_group.id})
      expect(result[:content].first[:text]).to include("deleted")
    end

    it "round-trips tag_names on metric_groups_create" do
      expect do
        described_class.call("metric_groups_create",
          { "name" => "Tagged Group", "tag_names" => ["alpha"] })
      end.to change(CompletionKit::Tag, :count).by(1)
      expect(CompletionKit::MetricGroup.find_by!(name: "Tagged Group").tag_names).to eq(["alpha"])
    end

    it "replaces tag_names on metric_groups_update" do
      group = create(:completion_kit_metric_group)
      group.update!(tag_names: ["a"])
      described_class.call("metric_groups_update",
        { "id" => group.id, "tag_names" => ["b"] })
      expect(group.reload.tag_names).to eq(["b"])
    end
  end
end
