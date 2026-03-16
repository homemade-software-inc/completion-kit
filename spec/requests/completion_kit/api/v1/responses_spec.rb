require "rails_helper"

RSpec.describe "API V1 Responses", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  let(:run) { create(:completion_kit_run) }

  describe "GET /api/v1/runs/:run_id/responses" do
    it "returns all responses for the run" do
      create(:completion_kit_response, run: run)
      create(:completion_kit_response, run: run)
      get "/completion_kit/api/v1/runs/#{run.id}/responses", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(2)
    end

    it "returns 404 for missing run" do
      get "/completion_kit/api/v1/runs/999999/responses", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/runs/:run_id/responses/:id" do
    it "returns a single response with reviews" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: resp)
      get "/completion_kit/api/v1/runs/#{run.id}/responses/#{resp.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["reviews"]).to be_an(Array)
      expect(body["reviews"].length).to eq(1)
    end

    it "returns 404 for response not belonging to run" do
      other_run = create(:completion_kit_run)
      resp = create(:completion_kit_response, run: other_run)
      get "/completion_kit/api/v1/runs/#{run.id}/responses/#{resp.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
