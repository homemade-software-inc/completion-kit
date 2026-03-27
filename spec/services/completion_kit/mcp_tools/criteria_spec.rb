require "rails_helper"

RSpec.describe CompletionKit::McpTools::Criteria do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        criteria_list criteria_get criteria_create criteria_update criteria_delete
      ])
    end
  end

  describe ".call" do
    let!(:criteria) { create(:completion_kit_criteria, name: "Quality") }

    it "lists criteria" do
      result = described_class.call("criteria_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Quality")
    end

    it "gets a criteria by id" do
      result = described_class.call("criteria_get", {"id" => criteria.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(criteria.id)
    end

    it "creates a criteria" do
      result = described_class.call("criteria_create", {"name" => "New Criteria"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Criteria")
    end

    it "creates a criteria with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("criteria_create", {"name" => "With Metrics", "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "updates a criteria" do
      result = described_class.call("criteria_update", {"id" => criteria.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "updates a criteria with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("criteria_update", {"id" => criteria.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "returns error on invalid create" do
      result = described_class.call("criteria_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("criteria_update", {"id" => criteria.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a criteria" do
      result = described_class.call("criteria_delete", {"id" => criteria.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
