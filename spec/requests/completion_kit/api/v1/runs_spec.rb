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

    it "creates a run with metric_ids" do
      prompt = create(:completion_kit_prompt)
      metric = create(:completion_kit_metric)
      post "/completion_kit/api/v1/runs",
        params: {prompt_id: prompt.id, metric_ids: [metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to eq([metric.id])
    end
  end

  describe "PATCH /api/v1/runs/:id" do
    it "updates the run" do
      run = create(:completion_kit_run)
      patch "/completion_kit/api/v1/runs/#{run.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      run = create(:completion_kit_run)
      patch "/completion_kit/api/v1/runs/#{run.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("errors")
    end

    it "updates a run with metric_ids" do
      run = create(:completion_kit_run)
      metric = create(:completion_kit_metric)
      patch "/completion_kit/api/v1/runs/#{run.id}",
        params: {metric_ids: [metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to eq([metric.id])
    end
  end

  describe "DELETE /api/v1/runs/:id" do
    it "deletes the run" do
      run = create(:completion_kit_run)
      delete "/completion_kit/api/v1/runs/#{run.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/runs/:id/retry_failures" do
    before { allow(CompletionKit::GenerateRowJob).to receive(:perform_later) }

    it "resets failed responses and returns 202" do
      run = create(:completion_kit_run, status: "completed")
      failed = create(:completion_kit_response, :failed, run: run, row_index: 0)

      post "/completion_kit/api/v1/runs/#{run.id}/retry_failures", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(failed.reload.status).to eq("pending")
      expect(run.reload.status).to eq("running")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed.id)
    end

    it "scopes to a single response when only param is supplied" do
      run = create(:completion_kit_run, status: "completed")
      failed_a = create(:completion_kit_response, :failed, run: run, row_index: 0)
      failed_b = create(:completion_kit_response, :failed, run: run, row_index: 1)

      post "/completion_kit/api/v1/runs/#{run.id}/retry_failures",
        params: {only: failed_a.id}.to_json,
        headers: headers

      expect(response).to have_http_status(:accepted)
      expect(failed_a.reload.status).to eq("pending")
      expect(failed_b.reload.status).to eq("failed")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed_a.id)
      expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later).with(run.id, failed_b.id)
    end
  end

  describe "POST /api/v1/runs/:id/generate" do
    it "calls start! and returns 202 on success" do
      run = create(:completion_kit_run)
      expect_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
      post "/completion_kit/api/v1/runs/#{run.id}/generate", headers: headers
      expect(response).to have_http_status(:accepted)
      expect(JSON.parse(response.body)["id"]).to eq(run.id)
    end

    it "returns 422 when start! fails" do
      run = create(:completion_kit_run)
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
      allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Cannot start run")
      post "/completion_kit/api/v1/runs/#{run.id}/generate", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to eq(["Cannot start run"])
    end
  end
end
