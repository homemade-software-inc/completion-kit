require "rails_helper"

RSpec.describe CompletionKit::McpTools::Metrics do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metrics_list metrics_get metrics_create metrics_update metrics_delete
      ])
    end
  end

  describe ".call" do
    let!(:metric) { create(:completion_kit_metric, name: "Accuracy") }

    it "lists metrics" do
      result = described_class.call("metrics_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Accuracy")
    end

    it "gets a metric by id" do
      result = described_class.call("metrics_get", {"id" => metric.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(metric.id)
    end

    it "creates a metric" do
      result = described_class.call("metrics_create", {"name" => "Tone", "instruction" => "Evaluate tone"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Tone")
    end

    it "creates a metric with rubric_bands" do
      result = described_class.call("metrics_create", {
        "name" => "Full", "instruction" => "Test",
        "rubric_bands" => [{"stars" => 5, "description" => "Perfect"}]
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["rubric_bands"].find { |b| b["stars"] == 5 }["description"]).to eq("Perfect")
    end

    it "updates a metric" do
      result = described_class.call("metrics_update", {"id" => metric.id, "name" => "Precision"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Precision")
    end

    it "returns error on invalid create" do
      result = described_class.call("metrics_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("metrics_update", {"id" => metric.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a metric" do
      result = described_class.call("metrics_delete", {"id" => metric.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
