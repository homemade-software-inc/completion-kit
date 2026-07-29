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

    it "excludes display-scoped-out runs from the list and the X-Total-Count header" do
      create(:completion_kit_run, name: "Recent API Run")
      create(:completion_kit_run, name: "Old API Run", created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      get "/completion_kit/api/v1/runs", headers: headers

      expect(JSON.parse(response.body).map { |r| r["name"] }).to contain_exactly("Recent API Run")
      expect(response.headers["X-Total-Count"]).to eq("1")
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "filters by status" do
      create(:completion_kit_run, status: "pending")
      done = create(:completion_kit_run, status: "completed")
      get "/completion_kit/api/v1/runs?status=completed", headers: headers
      ids = JSON.parse(response.body).map { |r| r["id"] }
      expect(ids).to eq([done.id])
    end

    it "filters by prompt_id and dataset_id" do
      prompt = create(:completion_kit_prompt, template: "Summarize {{content}} for {{audience}}")
      dataset = create(:completion_kit_dataset)
      matching = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      create(:completion_kit_run)
      get "/completion_kit/api/v1/runs?prompt_id=#{prompt.id}&dataset_id=#{dataset.id}", headers: headers
      ids = JSON.parse(response.body).map { |r| r["id"] }
      expect(ids).to eq([matching.id])
    end

    it "filters by one or more tags with OR semantics" do
      tagged_a = create(:completion_kit_run)
      tagged_a.update!(tag_names: ["alpha"])
      tagged_b = create(:completion_kit_run)
      tagged_b.update!(tag_names: ["beta"])
      create(:completion_kit_run)
      get "/completion_kit/api/v1/runs?tag[]=alpha&tag[]=beta", headers: headers
      ids = JSON.parse(response.body).map { |r| r["id"] }
      expect(ids).to contain_exactly(tagged_a.id, tagged_b.id)
    end

    it "paginates with limit + offset and exposes pagination headers" do
      runs = Array.new(3) { |i| create(:completion_kit_run, created_at: (3 - i).hours.ago) }
      get "/completion_kit/api/v1/runs?limit=2&offset=1", headers: headers
      ids = JSON.parse(response.body).map { |r| r["id"] }
      expect(ids).to eq([runs[1].id, runs[0].id])
      expect(response.headers["X-Total-Count"]).to eq("3")
      expect(response.headers["X-Limit"]).to eq("2")
      expect(response.headers["X-Offset"]).to eq("1")
    end

    it "clamps a non-positive limit back to the default and a negative offset back to zero" do
      create(:completion_kit_run)
      get "/completion_kit/api/v1/runs?limit=0&offset=-5", headers: headers
      expect(response.headers["X-Limit"]).to eq("50")
      expect(response.headers["X-Offset"]).to eq("0")
    end

    it "clamps a limit above the maximum back to the cap" do
      create(:completion_kit_run)
      get "/completion_kit/api/v1/runs?limit=10000", headers: headers
      expect(response.headers["X-Limit"]).to eq("500")
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
      expect(body).to have_key("check_pass_rate")
    end

    it "breaks the score down per metric so callers need not list responses" do
      run = create(:completion_kit_run)
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: resp, metric_name: "Tone", ai_score: 2.0)

      get "/completion_kit/api/v1/runs/#{run.id}", headers: headers

      expect(JSON.parse(response.body)["metric_averages"]).to eq(
        [{"name" => "Tone", "avg" => 2.0, "count" => 1, "low_count" => 1}]
      )
    end

    it "returns 404 for missing run" do
      get "/completion_kit/api/v1/runs/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/runs" do
    it "creates a run" do
      prompt = create(:completion_kit_prompt, template: "Static prompt")
      post "/completion_kit/api/v1/runs", params: {prompt_id: prompt.id}.to_json, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["status"]).to eq("pending")
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/runs", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates a run with metric_ids" do
      prompt = create(:completion_kit_prompt, template: "Static prompt")
      metric = create(:completion_kit_metric)
      post "/completion_kit/api/v1/runs",
        params: {prompt_id: prompt.id, metric_ids: [metric.id]}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["metric_ids"]).to eq([metric.id])
    end

    it "persists an expected_column answer-key override" do
      prompt = create(:completion_kit_prompt, template: "Static prompt")
      dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nphoto,WP0AA2A98KS103927\n")
      post "/completion_kit/api/v1/runs",
        params: {prompt_id: prompt.id, dataset_id: dataset.id, expected_column: "true_vin"}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["expected_column"]).to eq("true_vin")
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
      expect(JSON.parse(response.body)).to have_key("details")
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

    it "clears passed on a failed check review when retrying" do
      run = create(:completion_kit_run, status: "completed")
      metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text" })
      failed_row = create(:completion_kit_response, :failed, run: run, row_index: 0)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = failed_row.reviews.create!(metric: metric, metric_name: metric.name, metric_version_id: v1.id, status: "failed", passed: false, ai_score: nil)

      post "/completion_kit/api/v1/runs/#{run.id}/retry_failures", headers: headers

      expect(review.reload.passed).to be_nil
      expect(review.reload.status).to eq("pending")
    end

    it "returns 409 with a use-rerun message when reviews are stale against the current metric version" do
      run = create(:completion_kit_run, status: "completed")
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      response_row = create(:completion_kit_response, run: run, status: "succeeded", row_index: 0, response_text: "ok")
      create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id, status: "succeeded")
      failed_row = create(:completion_kit_response, :failed, run: run, row_index: 1)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!

      post "/completion_kit/api/v1/runs/#{run.id}/retry_failures", headers: headers

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to include("Judge has changed")
      expect(failed_row.reload.status).to eq("failed")
      expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later)
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
      expect(JSON.parse(response.body)["error"]).to eq("Cannot start run")
    end
  end

  describe "POST /api/v1/runs/:id/rerun" do
    it "creates a new run with the same configuration and returns 202" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
      expect { post "/completion_kit/api/v1/runs/#{run.id}/rerun", headers: headers }.to change { CompletionKit::Run.count }.by(1)
      expect(response).to have_http_status(:accepted)
    end

    it "returns 422 when the new run cannot start" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
      allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Dataset empty")
      post "/completion_kit/api/v1/runs/#{run.id}/rerun", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("Dataset empty")
    end

    it "copies the expected_column onto the new run" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nhi,X1\n")
      run = create(:completion_kit_run, prompt: prompt, dataset: dataset, expected_column: "true_vin")
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
      post "/completion_kit/api/v1/runs/#{run.id}/rerun", headers: headers
      expect(CompletionKit::Run.order(:id).last.expected_column).to eq("true_vin")
    end
  end

  describe "POST /api/v1/runs/:id/regrade" do
    before do
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    end

    it "re-grades succeeded responses with the current judge and returns 202" do
      metric = create(:completion_kit_metric)
      run = create(:completion_kit_run, judge_model: "gpt-4.1")
      CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
      response_row = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, status: "succeeded", metric_version_id: v1.id)
      post "/completion_kit/api/v1/runs/#{run.id}/regrade", headers: headers
      expect(response).to have_http_status(:accepted)
    end

    it "returns 422 when there is nothing to re-grade" do
      run = create(:completion_kit_run, judge_model: "gpt-4.1")
      post "/completion_kit/api/v1/runs/#{run.id}/regrade", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("Nothing to re-grade")
    end
  end

  describe "GET /api/v1/runs/:id/compare" do
    it "returns side-by-side per-case-per-metric scores and deltas" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      left = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      right = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      metric = create(:completion_kit_metric)
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      left_response = create(:completion_kit_response, run: left, input_data: "hi", response_text: "a")
      right_response = create(:completion_kit_response, run: right, input_data: "hi", response_text: "b")
      create(:completion_kit_review, response: left_response, metric: metric, metric_name: metric.name, ai_score: 5, status: "succeeded", metric_version_id: v1.id)
      create(:completion_kit_review, response: right_response, metric: metric, metric_name: metric.name, ai_score: 3, status: "succeeded", metric_version_id: v1.id)

      get "/completion_kit/api/v1/runs/#{left.id}/compare", params: { with: right.id }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["left_run_id"]).to eq(left.id)
      expect(body["right_run_id"]).to eq(right.id)
      first_row = body["rows"].first
      pm = first_row["per_metric"].first
      expect(pm["left_score"].to_f).to eq(5.0)
      expect(pm["right_score"].to_f).to eq(3.0)
      expect(pm["delta"].to_f).to eq(-2.0)
    end

    it "returns 404 when the with= run does not exist" do
      run = create(:completion_kit_run)
      get "/completion_kit/api/v1/runs/#{run.id}/compare", params: { with: 9999999 }, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "surfaces a check pass to fail as result_change broke (the CI gate)" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      left = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      right = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      check = create(:completion_kit_metric, :check)
      v1 = CompletionKit::MetricVersion.ensure_current_for(check)
      left_response = create(:completion_kit_response, run: left, input_data: "hi", response_text: '{"ok":1}')
      right_response = create(:completion_kit_response, run: right, input_data: "hi", response_text: "not json")
      create(:completion_kit_review, :check, response: left_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: true)
      create(:completion_kit_review, :check, response: right_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: false)

      get "/completion_kit/api/v1/runs/#{left.id}/compare", params: { with: right.id }, headers: headers

      pm = JSON.parse(response.body)["rows"].first["per_metric"].first
      expect(pm["kind"]).to eq("check")
      expect(pm["left_passed"]).to be(true)
      expect(pm["right_passed"]).to be(false)
      expect(pm["result_change"]).to eq("broke")
    end

    it "reports result_change nil for a one-sided check review" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      left = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      right = create(:completion_kit_run, prompt: prompt, dataset: dataset)
      check = create(:completion_kit_metric, :check)
      v1 = CompletionKit::MetricVersion.ensure_current_for(check)
      left_response = create(:completion_kit_response, run: left, input_data: "hi", response_text: "x")
      create(:completion_kit_response, run: right, input_data: "hi", response_text: "y")
      create(:completion_kit_review, :check, response: left_response, metric: check, metric_name: check.name, metric_version_id: v1.id, passed: true)

      get "/completion_kit/api/v1/runs/#{left.id}/compare", params: { with: right.id }, headers: headers

      pm = JSON.parse(response.body)["rows"].first["per_metric"].first
      expect(pm["result_change"]).to be_nil
      expect(pm["right_passed"]).to be_nil
    end

    it "tolerates mixed shapes: left-only metric review, right-only metric review, and an orphan response on the left with no matching right" do
      prompt = create(:completion_kit_prompt, template: "Static")
      dataset = create(:completion_kit_dataset, csv_data: "input\nhi\n")
      left = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      right = create(:completion_kit_run, prompt: prompt, dataset: dataset, judge_model: "gpt-4.1")
      metric_a = create(:completion_kit_metric, name: "Both-sides metric")
      metric_b = create(:completion_kit_metric, name: "Right-only metric")
      v_a = CompletionKit::MetricVersion.ensure_current_for(metric_a)
      v_b = CompletionKit::MetricVersion.ensure_current_for(metric_b)
      # Shared input: left has metric_a only, right has metric_b only -> exercises left-only / right-only branches
      shared_left = create(:completion_kit_response, run: left, input_data: "shared", response_text: "L")
      shared_right = create(:completion_kit_response, run: right, input_data: "shared", response_text: "R")
      create(:completion_kit_review, response: shared_left, metric: metric_a, metric_name: metric_a.name, ai_score: 4.0, status: "succeeded", metric_version_id: v_a.id)
      create(:completion_kit_review, response: shared_right, metric: metric_b, metric_name: metric_b.name, ai_score: 2.0, status: "succeeded", metric_version_id: v_b.id)
      # Orphan left response: no matching right input -> exercises rr&.id else and "neither side has review" skip
      orphan_left = create(:completion_kit_response, run: left, input_data: "orphan-only-left", response_text: "X")
      create(:completion_kit_review, response: orphan_left, metric: metric_a, metric_name: metric_a.name, ai_score: 5.0, status: "succeeded", metric_version_id: v_a.id)

      get "/completion_kit/api/v1/runs/#{left.id}/compare", params: { with: right.id }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      shared_row = body["rows"].find { |r| r["left_response_id"] == shared_left.id }
      orphan_row = body["rows"].find { |r| r["left_response_id"] == orphan_left.id }
      expect(shared_row["per_metric"].size).to eq(2)
      expect(orphan_row["right_response_id"]).to be_nil
      orphan_metric_a = orphan_row["per_metric"].find { |pm| pm["metric_id"] == metric_a.id }
      expect(orphan_metric_a["right_score"]).to be_nil
      expect(orphan_metric_a["delta"]).to be_nil
    end
  end

  describe "tag_names round-trip" do
    let(:prompt) { create(:completion_kit_prompt, template: "Static prompt") }

    it "auto-creates new tags on POST and includes them in the response" do
      expect do
        post "/completion_kit/api/v1/runs",
          params: { prompt_id: prompt.id, tag_names: ["new"] }.to_json,
          headers: headers
      end.to change(CompletionKit::Tag, :count).by(1)
      run = CompletionKit::Run.find(JSON.parse(response.body)["id"])
      expect(run.tag_names).to eq(["new"])
      expect(JSON.parse(response.body)["tags"].map { |t| t["name"] }).to eq(["new"])
    end

    it "replaces tags on PATCH" do
      run = create(:completion_kit_run)
      run.update!(tag_names: ["a", "b"])
      patch "/completion_kit/api/v1/runs/#{run.id}",
        params: { tag_names: ["c"] }.to_json,
        headers: headers
      expect(run.reload.tag_names).to eq(["c"])
    end

    it "clears all tags on PATCH with empty array" do
      run = create(:completion_kit_run)
      run.update!(tag_names: ["a"])
      patch "/completion_kit/api/v1/runs/#{run.id}",
        params: { tag_names: [] }.to_json,
        headers: headers
      expect(run.reload.tag_names).to eq([])
    end

    it "exposes tags in GET show" do
      run = create(:completion_kit_run)
      run.update!(tag_names: ["alpha"])
      get "/completion_kit/api/v1/runs/#{run.id}", headers: headers
      body = JSON.parse(response.body)
      expect(body["tags"].map { |t| t["name"] }).to eq(["alpha"])
    end
  end
end
