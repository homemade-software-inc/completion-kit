require "rails_helper"

RSpec.describe "API V1 Runs", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/runs" do
    it "returns all runs ordered by created_at desc" do
      old = create(:completion_kit_run, created_at: 1.day.ago)
      recent = create(:completion_kit_run, created_at: 1.hour.ago)
      get "/completion_kit/api/v1/runs", headers: headers
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |r| r["id"] }
      expect(ids).to eq([recent.id, old.id])
    end
  end

  describe "GET /api/v1/runs/:id" do
    it "returns the run with computed fields" do
      run = create(:completion_kit_run)
      create(:completion_kit_response, run: run)
      get "/completion_kit/api/v1/runs/#{run.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["responses_count"]).to eq(1)
      expect(body).to have_key("avg_score")
    end

    it "returns 404 for missing run" do
      get "/completion_kit/api/v1/runs/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/runs" do
    it "creates a run" do
      prompt = create(:completion_kit_prompt)
      post "/completion_kit/api/v1/runs", params: {prompt_id: prompt.id}.to_json, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("pending")
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/runs", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/runs/:id" do
    it "updates the run" do
      run = create(:completion_kit_run)
      patch "/completion_kit/api/v1/runs/#{run.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end
  end

  describe "DELETE /api/v1/runs/:id" do
    it "deletes the run" do
      run = create(:completion_kit_run)
      delete "/completion_kit/api/v1/runs/#{run.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/runs/:id/generate" do
    it "generates responses and returns updated run" do
      run = create(:completion_kit_run)
      allow_any_instance_of(CompletionKit::Run).to receive(:generate_responses!).and_return(true)
      post "/completion_kit/api/v1/runs/#{run.id}/generate", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 422 when generation fails" do
      run = create(:completion_kit_run)
      allow_any_instance_of(CompletionKit::Run).to receive(:generate_responses!) do |r|
        r.update_column(:status, "failed")
        false
      end
      post "/completion_kit/api/v1/runs/#{run.id}/generate", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Generation failed")
    end
  end

  describe "POST /api/v1/runs/:id/judge" do
    it "judges responses and returns updated run" do
      run = create(:completion_kit_run)
      allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!).and_return(true)
      post "/completion_kit/api/v1/runs/#{run.id}/judge", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns 422 when judging fails" do
      run = create(:completion_kit_run)
      allow_any_instance_of(CompletionKit::Run).to receive(:judge_responses!) do |r|
        r.update_column(:status, "failed")
        false
      end
      post "/completion_kit/api/v1/runs/#{run.id}/judge", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Judging failed")
    end
  end
end
