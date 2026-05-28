require "rails_helper"

RSpec.describe CompletionKit::McpTools::MetricVersions, type: :service do
  let(:metric) { create(:completion_kit_metric, instruction: "v1 instruction") }

  describe "metric_versions_list" do
    it "returns every MetricVersion for the metric, newest version_number first" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      result = CompletionKit::McpTools::MetricVersions.call("metric_versions_list", { "metric_id" => metric.id })
      parsed = JSON.parse(result[:content].first[:text])
      expect(parsed.map { |v| v["version_number"] }).to eq([v2.version_number, v1.version_number])
      expect(parsed.first["source"]).to eq("edit")
    end
  end

  describe "metric_versions_publish" do
    it "publishes a draft as current and writes its content back to the metric" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2 instruction", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")

      result = CompletionKit::McpTools::MetricVersions.call("metric_versions_publish", { "metric_version_id" => v2.id })
      parsed = JSON.parse(result[:content].first[:text])

      expect(parsed["state"]).to eq("published")
      expect(parsed["current"]).to be(true)
      expect(metric.reload.instruction).to eq("v2 instruction")
      expect(v1.reload.current).to be(false)
    end

    it "reverts to an older published version by re-publishing it as current" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      expect(v1.reload.current).to be(false)

      result = CompletionKit::McpTools::MetricVersions.call("metric_versions_publish", { "metric_version_id" => v1.id })
      parsed = JSON.parse(result[:content].first[:text])

      expect(parsed["current"]).to be(true)
      expect(metric.reload.instruction).to eq("v1 instruction")
      expect(v2.reload.current).to be(false)
    end
  end

  describe "metric_versions_dismiss" do
    it "destroys a draft version and returns a destroyed marker" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      draft = CompletionKit::MetricVersion.create!(metric: metric, instruction: "throwaway", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
      result = CompletionKit::McpTools::MetricVersions.call("metric_versions_dismiss", { "metric_version_id" => draft.id })
      parsed = JSON.parse(result[:content].first[:text])
      expect(parsed["destroyed"]).to be(true)
      expect(CompletionKit::MetricVersion.where(id: draft.id)).to be_empty
    end

    it "refuses to destroy a published version and returns an error_result" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      result = CompletionKit::McpTools::MetricVersions.call("metric_versions_dismiss", { "metric_version_id" => v1.id })
      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to include("Cannot dismiss a published version")
      expect(CompletionKit::MetricVersion.where(id: v1.id)).to exist
    end
  end
end
