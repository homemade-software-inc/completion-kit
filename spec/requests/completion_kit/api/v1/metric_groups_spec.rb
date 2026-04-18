require "rails_helper"

RSpec.describe "API V1 Metric Groups", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/metric_groups" do
    it "returns all metric groups" do
      create(:completion_kit_metric_group)
      get "/completion_kit/api/v1/metric_groups", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe "GET /api/v1/metric_groups/:id" do
    it "returns the metric group with metric_ids" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      get "/completion_kit/api/v1/metric_groups/#{metric_group.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to be_an(Array)
      expect(body["metric_ids"].length).to be > 0
    end

    it "returns 404 for missing metric group" do
      get "/completion_kit/api/v1/metric_groups/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/metric_groups" do
    it "creates a metric group with metrics" do
      metric = create(:completion_kit_metric)
      post "/completion_kit/api/v1/metric_groups",
        params: {name: "quality", metric_ids: [metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to eq([metric.id])
    end

    it "creates a metric group without metrics" do
      post "/completion_kit/api/v1/metric_groups",
        params: {name: "simple"}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/metric_groups", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/metric_groups/:id" do
    it "updates a metric group" do
      metric_group = create(:completion_kit_metric_group)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      metric_group = create(:completion_kit_metric_group)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "replaces metric associations" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      new_metric = create(:completion_kit_metric)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}",
        params: {metric_ids: [new_metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["metric_ids"]).to eq([new_metric.id])
    end

    it "handles nil metric_ids" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      patch "/completion_kit/api/v1/metric_groups/#{metric_group.id}",
        params: {name: "updated", metric_ids: nil}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE /api/v1/metric_groups/:id" do
    it "deletes a metric group" do
      metric_group = create(:completion_kit_metric_group)
      delete "/completion_kit/api/v1/metric_groups/#{metric_group.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
