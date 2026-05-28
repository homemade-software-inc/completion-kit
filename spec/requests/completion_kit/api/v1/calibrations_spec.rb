require "rails_helper"

RSpec.describe "API V1 Calibrations", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  let(:run) { create(:completion_kit_run) }
  let(:response_row) { create(:completion_kit_response, run: run) }
  let(:metric) { create(:completion_kit_metric) }

  def base_path
    "/completion_kit/api/v1/runs/#{run.id}/responses/#{response_row.id}/metrics/#{metric.id}/calibrations"
  end

  describe "GET /api/v1/calibrations (flat index)" do
    let(:other_run) { create(:completion_kit_run) }
    let(:other_response) { create(:completion_kit_response, run: other_run) }
    let(:other_metric) { create(:completion_kit_metric, name: "Other") }

    before do
      mv = CompletionKit::MetricVersion.ensure_current_for(metric)
      mv_other = CompletionKit::MetricVersion.ensure_current_for(other_metric)
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric, metric_version: mv,
             verdict: "agree", created_by: "alice")
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric, metric_version: mv,
             verdict: "disagree", corrected_score: 2.0, created_by: "bob")
      create(:completion_kit_calibration,
             run: other_run, response: other_response, metric: other_metric, metric_version: mv_other,
             verdict: "borderline", created_by: "alice")
    end

    it "returns every calibration when no filter is supplied" do
      get "/completion_kit/api/v1/calibrations", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end

    it "filters by metric_id" do
      get "/completion_kit/api/v1/calibrations", params: { metric_id: metric.id }, headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it "filters by run_id" do
      get "/completion_kit/api/v1/calibrations", params: { run_id: run.id }, headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it "filters by response_id" do
      get "/completion_kit/api/v1/calibrations", params: { response_id: response_row.id }, headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it "filters by metric_version_id" do
      mv = CompletionKit::MetricVersion.current.find_by(metric_id: metric.id)
      get "/completion_kit/api/v1/calibrations", params: { metric_version_id: mv.id }, headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it "filters by created_by" do
      get "/completion_kit/api/v1/calibrations", params: { created_by: "alice" }, headers: headers
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it "filters by verdict" do
      get "/completion_kit/api/v1/calibrations", params: { verdict: "disagree" }, headers: headers
      expect(JSON.parse(response.body).size).to eq(1)
    end
  end

  describe "DELETE /api/v1/calibrations/:id" do
    it "destroys a calibration and returns 204" do
      mv = CompletionKit::MetricVersion.ensure_current_for(metric)
      cal = create(:completion_kit_calibration,
                   run: run, response: response_row, metric: metric, metric_version: mv,
                   verdict: "agree", created_by: "alice")
      delete "/completion_kit/api/v1/calibrations/#{cal.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(CompletionKit::Calibration.where(id: cal.id)).to be_empty
    end

    it "returns 404 when the calibration does not exist" do
      delete "/completion_kit/api/v1/calibrations/9999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST" do
    it "creates an agree calibration without a corrected score" do
      post base_path, headers: headers,
                      params: { verdict: "agree", created_by: "alice" }.to_json
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["verdict"]).to eq("agree")
      expect(body["created_by"]).to eq("alice")
      expect(body["metric_version_id"]).to be_present
    end

    it "upserts on subsequent POST with the same (response, metric, created_by)" do
      post base_path, headers: headers,
                      params: { verdict: "agree", created_by: "alice" }.to_json
      first_id = JSON.parse(response.body)["id"]
      post base_path, headers: headers,
                      params: { verdict: "disagree", corrected_score: 3.0, created_by: "alice" }.to_json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(first_id)
      expect(body["verdict"]).to eq("disagree")
      expect(body["corrected_score"].to_f).to eq(3.0)
    end

    it "defaults created_by to 'api' when not provided" do
      post base_path, headers: headers, params: { verdict: "borderline" }.to_json
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["created_by"]).to eq("api")
    end

    it "returns 422 on validation error" do
      post base_path, headers: headers,
                      params: { verdict: "disagree", created_by: "alice" }.to_json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    it "returns 404 when the run, response, or metric is missing" do
      post "/completion_kit/api/v1/runs/999/responses/999/metrics/999/calibrations",
           headers: headers,
           params: { verdict: "agree" }.to_json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the calibration feature flag is off" do
      original = CompletionKit.config.judge_calibration_enabled
      CompletionKit.config.judge_calibration_enabled = false
      post base_path, headers: headers, params: { verdict: "agree" }.to_json
      expect(response).to have_http_status(:not_found)
    ensure
      CompletionKit.config.judge_calibration_enabled = original
    end
  end

  describe "GET" do
    it "lists calibrations for the (run, response, metric) triple" do
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric,
             metric_version: jv, created_by: "alice")
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric,
             metric_version: jv, created_by: "bob", verdict: "borderline")
      get base_path, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
      verdicts = body.map { |c| c["verdict"] }
      expect(verdicts).to contain_exactly("agree", "borderline")
    end
  end
end
