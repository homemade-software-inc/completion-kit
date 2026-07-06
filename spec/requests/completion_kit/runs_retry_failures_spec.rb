require "rails_helper"

RSpec.describe "POST /completion_kit/runs/:id/retry_failures", type: :request do
  let(:run) { create(:completion_kit_run, status: "completed") }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
  end

  it "refuses retry when any review in the run is stale against the current metric_version, and points the user at Re-run with current judge" do
    metric = create(:completion_kit_metric)
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    response_row = create(:completion_kit_response, run: run, status: "succeeded", row_index: 0, response_text: "ok")
    create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id, status: "succeeded")
    failed_row = create(:completion_kit_response, :failed, run: run, row_index: 1)
    v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!

    post "/completion_kit/runs/#{run.id}/retry_failures"

    expect(response).to redirect_to("/completion_kit/runs/#{run.id}")
    follow_redirect!
    expect(response.body).to include("Re-grade with current metrics")
    expect(failed_row.reload.status).to eq("failed")
    expect(run.reload.status).to eq("completed")
    expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later)
  end

  it "clears passed on a failed check review when retrying" do
    metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text" })
    failed_row = create(:completion_kit_response, :failed, run: run, row_index: 0)
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = failed_row.reviews.create!(metric: metric, metric_name: metric.name, metric_version_id: v1.id, status: "failed", passed: false, ai_score: nil)

    post "/completion_kit/runs/#{run.id}/retry_failures"

    expect(review.reload.passed).to be_nil
    expect(review.reload.status).to eq("pending")
  end

  it "fires on_run_started because retry_failures transitions the run back to running" do
    metric = create(:completion_kit_metric, :check, check_config: { "check_kind" => "valid_json", "target" => "response_text" })
    failed_row = create(:completion_kit_response, :failed, run: run, row_index: 0)
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    failed_row.reviews.create!(metric: metric, metric_name: metric.name, metric_version_id: v1.id, status: "failed", passed: false, ai_score: nil)
    observed = []
    CompletionKit.config.on_run_started = ->(r) { observed << r.id }

    post "/completion_kit/runs/#{run.id}/retry_failures"

    expect(observed).to eq([run.id])
  ensure
    CompletionKit.config.on_run_started = nil
  end

  it "resets failed responses to pending and re-enqueues their jobs" do
    failed = create(:completion_kit_response, :failed, run: run, row_index: 0)
    succeeded = create(:completion_kit_response, run: run, status: "succeeded", row_index: 1, response_text: "ok")

    post "/completion_kit/runs/#{run.id}/retry_failures"

    failed.reload
    succeeded.reload

    expect(failed.status).to eq("pending")
    expect(failed.error_class).to be_nil
    expect(failed.attempts).to eq(0)
    expect(succeeded.status).to eq("succeeded")
    expect(run.reload.status).to eq("running")
    expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed.id)
    expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later).with(run.id, succeeded.id)
  end

  it "scopes to a single response when only param is supplied" do
    failed_a = create(:completion_kit_response, :failed, run: run, row_index: 0)
    failed_b = create(:completion_kit_response, :failed, run: run, row_index: 1)

    post "/completion_kit/runs/#{run.id}/retry_failures", params: { only: failed_a.id }

    expect(failed_a.reload.status).to eq("pending")
    expect(failed_b.reload.status).to eq("failed")
    expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed_a.id)
    expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later).with(run.id, failed_b.id)
  end
end
