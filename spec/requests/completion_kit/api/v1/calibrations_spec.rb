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

  describe "POST" do
    it "creates an agree calibration without a corrected score" do
      post base_path, headers: headers,
                      params: { verdict: "agree", created_by: "alice" }.to_json
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["verdict"]).to eq("agree")
      expect(body["created_by"]).to eq("alice")
      expect(body["judge_version_id"]).to be_present
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
  end

  describe "GET" do
    it "lists calibrations for the (run, response, metric) triple" do
      jv = CompletionKit::JudgeVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric,
             judge_version: jv, created_by: "alice")
      create(:completion_kit_calibration,
             run: run, response: response_row, metric: metric,
             judge_version: jv, created_by: "bob", verdict: "borderline")
      get base_path, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
      verdicts = body.map { |c| c["verdict"] }
      expect(verdicts).to contain_exactly("agree", "borderline")
    end
  end
end
