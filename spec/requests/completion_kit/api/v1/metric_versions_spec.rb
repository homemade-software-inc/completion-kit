require "rails_helper"

RSpec.describe "API V1 MetricVersions", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  let(:metric) { create(:completion_kit_metric, instruction: "v1 instruction") }

  describe "GET /api/v1/metrics/:metric_id/metric_versions" do
    it "returns every version for the metric, newest version_number first" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      get "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |v| v["version_number"] }).to eq([v2.version_number, v1.version_number])
    end

    it "returns 404 when the metric does not exist" do
      get "/completion_kit/api/v1/metrics/9999999/metric_versions", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/metrics/:metric_id/metric_versions/:id" do
    it "returns the version payload" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      get "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{v1.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(v1.id)
    end

    it "returns 404 when the version does not exist" do
      get "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/9999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/metrics/:metric_id/metric_versions/:id/publish" do
    it "publishes a draft as current and writes its content back to the metric" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      draft = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2 instruction", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
      post "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{draft.id}/publish", headers: headers
      expect(response).to have_http_status(:ok)
      expect(metric.reload.instruction).to eq("v2 instruction")
    end

    it "reverts to an older published version when called on a superseded one" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      expect(v1.reload.current).to be(false)

      post "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{v1.id}/publish", headers: headers
      expect(response).to have_http_status(:ok)
      expect(v1.reload.current).to be(true)
      expect(metric.reload.instruction).to eq("v1 instruction")
    end
  end

  describe "DELETE /api/v1/metrics/:metric_id/metric_versions/:id" do
    it "destroys a draft version and returns 204" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      draft = CompletionKit::MetricVersion.create!(metric: metric, instruction: "scrap", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
      delete "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{draft.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "refuses to destroy a published version and returns 409" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      delete "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{v1.id}", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to include("Cannot dismiss a published version")
    end
  end
end
