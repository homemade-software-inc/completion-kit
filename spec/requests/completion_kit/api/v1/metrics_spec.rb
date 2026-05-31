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
      expect(JSON.parse(response.body)).to have_key("details")
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

  describe "POST /api/v1/metrics/:id/suggest_variants" do
    def stub_llm(text)
      client = instance_double("CompletionKit::OpenAiClient")
      allow(client).to receive(:generate_completion).and_return(text)
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
    end

    let(:metric) { create(:completion_kit_metric) }
    let(:run) { create(:completion_kit_run) }
    let(:response_row) { create(:completion_kit_response, run: run) }

    def add_disagree(corrected: 3, note: "off")
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: response_row, metric: metric,
             metric_version: jv, verdict: "disagree",
             corrected_score: corrected, note: note, created_by: SecureRandom.uuid)
    end

    it "creates draft suggestion versions and returns 201" do
      add_disagree
      stub_llm("VARIANT:\nREASONING: tighter\nINSTRUCTION:\nbe sharper\nEND_VARIANT")
      post "/completion_kit/api/v1/metrics/#{metric.id}/suggest_variants", headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).first["source"]).to eq("suggestion")
    end

    it "returns 422 when no disagreements exist" do
      post "/completion_kit/api/v1/metrics/#{metric.id}/suggest_variants", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("Mark at least one case as Disagree")
    end

    it "returns 422 when the model returns nothing usable" do
      add_disagree
      stub_llm("not a variant block")
      post "/completion_kit/api/v1/metrics/#{metric.id}/suggest_variants", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("no usable variants")
    end
  end

end
