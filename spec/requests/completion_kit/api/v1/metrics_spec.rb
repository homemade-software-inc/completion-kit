require "rails_helper"

RSpec.describe "API V1 Metrics", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/metrics" do
    it "returns all metrics" do
      create(:completion_kit_metric)
      get "/completion_kit/api/v1/metrics", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe "GET /api/v1/metrics/:id" do
    it "returns the metric" do
      metric = create(:completion_kit_metric)
      get "/completion_kit/api/v1/metrics/#{metric.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for missing metric" do
      get "/completion_kit/api/v1/metrics/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/metrics" do
    it "creates a metric" do
      post "/completion_kit/api/v1/metrics",
        params: {name: "relevance", instruction: "Is the response relevant?"}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/metrics", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/metrics/:id" do
    it "updates the metric" do
      metric = create(:completion_kit_metric)
      patch "/completion_kit/api/v1/metrics/#{metric.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      metric = create(:completion_kit_metric)
      patch "/completion_kit/api/v1/metrics/#{metric.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("errors")
    end
  end

  describe "DELETE /api/v1/metrics/:id" do
    it "deletes the metric" do
      metric = create(:completion_kit_metric)
      delete "/completion_kit/api/v1/metrics/#{metric.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "tag_names round-trip" do
    it "auto-creates new tags on POST and includes them in the response" do
      expect do
        post "/completion_kit/api/v1/metrics",
          params: { name: "T", instruction: "x", tag_names: ["new"] }.to_json,
          headers: headers
      end.to change(CompletionKit::Tag, :count).by(1)
      metric = CompletionKit::Metric.find_by!(name: "T")
      expect(metric.tag_names).to eq(["new"])
      body = JSON.parse(response.body)
      expect(body["tags"].map { |t| t["name"] }).to eq(["new"])
    end

    it "replaces tags on PATCH" do
      metric = create(:completion_kit_metric)
      metric.update!(tag_names: ["a", "b"])
      patch "/completion_kit/api/v1/metrics/#{metric.id}",
        params: { tag_names: ["c"] }.to_json,
        headers: headers
      expect(metric.reload.tag_names).to eq(["c"])
    end

    it "clears all tags on PATCH with empty array" do
      metric = create(:completion_kit_metric)
      metric.update!(tag_names: ["a"])
      patch "/completion_kit/api/v1/metrics/#{metric.id}",
        params: { tag_names: [] }.to_json,
        headers: headers
      expect(metric.reload.tag_names).to eq([])
    end

    it "exposes tags in GET show" do
      metric = create(:completion_kit_metric)
      metric.update!(tag_names: ["alpha"])
      get "/completion_kit/api/v1/metrics/#{metric.id}", headers: headers
      body = JSON.parse(response.body)
      expect(body["tags"].map { |t| t["name"] }).to eq(["alpha"])
    end
  end
end
