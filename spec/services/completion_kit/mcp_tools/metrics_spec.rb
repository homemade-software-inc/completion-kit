require "rails_helper"

RSpec.describe CompletionKit::McpTools::Metrics do
  describe ".definitions" do
    it "returns 6 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(6)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        metrics_list metrics_get metrics_create metrics_update metrics_delete metrics_suggest_variants
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

    it "creates a check metric with metric_type and check_config" do
      result = described_class.call("metrics_create", {
        "name" => "Contains OK", "metric_type" => "check",
        "check_config" => {"check_kind" => "contains", "target" => "response_text", "value" => "OK"}
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_type"]).to eq("check")
      expect(content["check_config"]).to include("value" => "OK")
    end

    it "updates a check metric's check_config" do
      check = create(:completion_kit_metric, :check)
      result = described_class.call("metrics_update", {
        "id" => check.id,
        "check_config" => {"check_kind" => "contains", "target" => "response_text", "value" => "done"}
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["check_config"]).to include("value" => "done")
    end

    it "advertises metric_type and check_config on the create and update schemas" do
      %w[metrics_create metrics_update].each do |tool|
        schema = described_class::TOOLS[tool][:inputSchema]
        expect(schema[:properties]).to have_key(:metric_type)
        expect(schema[:properties][:metric_type][:enum]).to include("check")
        expect(schema[:properties]).to have_key(:check_config)
      end
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

    it "round-trips tag_names on metrics_create with auto-create" do
      expect do
        described_class.call("metrics_create",
          {"name" => "T", "instruction" => "x", "tag_names" => ["new"]})
      end.to change(CompletionKit::Tag, :count).by(1)
      found = CompletionKit::Metric.find_by!(name: "T")
      expect(found.tag_names).to eq(["new"])
    end

    it "replaces tag_names on metrics_update" do
      metric.update!(tag_names: ["a", "b"])
      described_class.call("metrics_update", {"id" => metric.id, "tag_names" => ["c"]})
      expect(metric.reload.tag_names).to eq(["c"])
    end
  end
end
