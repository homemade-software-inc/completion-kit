require "rails_helper"

RSpec.describe "CompletionKit responses", type: :request do
  let!(:metric_group) { create(:completion_kit_metric_group, :with_metrics) }
  let!(:prompt) { create(:completion_kit_prompt) }
  let!(:run) { create(:completion_kit_run, prompt: prompt, name: "Run Results") }
  let!(:response_with_output) { create(:completion_kit_response, run: run, response_text: "alpha beta", expected_output: "alpha beta") }
  let!(:response_without_expected) { create(:completion_kit_response, run: run, response_text: "delta", expected_output: nil) }

  before do
    metric_group.metrics.each do |metric|
      create(:completion_kit_review, response: response_with_output, metric: metric, metric_name: metric.name, ai_score: 4.5, ai_feedback: "Solid #{metric.name}")
    end
  end

  it "renders show with reviews" do
    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Response")
    expect(response.body).to include(metric_group.metrics.first.name)
  end

  it "marks a stale review with a concise version-transition chip and no border accent" do
    metric = metric_group.metrics.first
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: v1.id)
    v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}"

    expect(response.body).to include("ck-source-chip--past")
    expect(response.body).to include("v1 &rarr; v2")
    expect(response.body).to include("the metric is now on")
    expect(response.body).not_to include("Scored against a superseded version")
    expect(response.body).not_to include("ck-review-card--stale")
  end

  describe "GET /runs/:id/compare" do
    it "renders the picker view listing other runs on the same dataset + prompt when no with= is supplied" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Earlier run")
      get "/completion_kit/runs/#{run.id}/compare"
      expect(response.body).to include("Compare with another run")
      expect(response.body).to include("Earlier run")
    end

    it "shows the no-other-runs empty state when there are no candidates" do
      other_prompt = create(:completion_kit_prompt)
      create(:completion_kit_run, prompt: other_prompt, name: "Different prompt")
      get "/completion_kit/runs/#{run.id}/compare"
      expect(response.body).to include("No other runs on this dataset")
    end

    it "renders the side-by-side comparison when with= is supplied" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Sibling run")
      metric = metric_group.metrics.first
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      sibling_response = create(:completion_kit_response, run: sibling, input_data: response_with_output.input_data, response_text: "different reply")
      create(:completion_kit_review, response: sibling_response, metric: metric, metric_name: metric.name, ai_score: 2.0, status: "succeeded", metric_version_id: v1.id)
      review = response_with_output.reviews.find_by(metric_id: metric.id)
      review.update!(metric_version_id: v1.id)

      get "/completion_kit/runs/#{run.id}/compare?with=#{sibling.id}"

      expect(response.body).to include("Comparing runs")
      expect(response.body).to include(metric.name)
      expect(response.body).to include("ck-delta")
      expect(response.body).to include("ck-run-compare-table")
    end

    it "renders the empty-rows message when neither run has reviews" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Empty sibling")
      empty_run = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Also empty")
      get "/completion_kit/runs/#{empty_run.id}/compare?with=#{sibling.id}"
      expect(response.body).to include("No responses to compare")
    end

    it "renders score badges without a delta when one side has no review for the metric" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Half-judged")
      metric = metric_group.metrics.first
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = response_with_output.reviews.find_by(metric_id: metric.id)
      review.update!(metric_version_id: v1.id)
      sibling_response = create(:completion_kit_response, run: sibling, input_data: response_with_output.input_data, response_text: "skipped grading")

      get "/completion_kit/runs/#{run.id}/compare?with=#{sibling.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(metric.name)
    end

    it "leaves the version chip blank when a review's metric_version_id has been deleted out from under it" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Ghost-version sibling")
      metric = metric_group.metrics.first
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      review = response_with_output.reviews.find_by(metric_id: metric.id)
      review.update!(metric_version_id: v1.id)
      sibling_response = create(:completion_kit_response, run: sibling, input_data: response_with_output.input_data, response_text: "ghost")
      ghost_review = create(:completion_kit_review, response: sibling_response, metric: metric, metric_name: metric.name, ai_score: 3.0, status: "succeeded", metric_version_id: v1.id)
      # Delete v1 so the review's metric_version_id no longer resolves to a row.
      v1.delete

      get "/completion_kit/runs/#{run.id}/compare?with=#{sibling.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(metric.name)
    end

    it "tolerates left-side cases that have no matching right-side response, and right-only metrics on matched cases" do
      sibling = create(:completion_kit_run, prompt: prompt, dataset: run.dataset, name: "Mismatched")
      metric_a = metric_group.metrics.first
      metric_b = create(:completion_kit_metric, name: "Right-only metric")
      v1a = CompletionKit::MetricVersion.ensure_current_for(metric_a)
      v1b = CompletionKit::MetricVersion.ensure_current_for(metric_b)
      # Left run: response_with_output (matched on the right) and response_without_expected (NOT matched on the right). Give the unmatched one a review so its row renders, exercising the rr-is-nil branches.
      review_a_on_left = create(:completion_kit_review, response: response_without_expected, metric: metric_a, metric_name: metric_a.name, ai_score: 4.0, status: "succeeded", metric_version_id: v1a.id)
      review = response_with_output.reviews.find_by(metric_id: metric_a.id)
      review.update!(metric_version_id: v1a.id)
      sibling_response = create(:completion_kit_response, run: sibling, input_data: response_with_output.input_data, response_text: "judged on a different metric")
      create(:completion_kit_review, response: sibling_response, metric: metric_b, metric_name: metric_b.name, ai_score: 3.5, status: "succeeded", metric_version_id: v1b.id)

      get "/completion_kit/runs/#{run.id}/compare?with=#{sibling.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(metric_a.name)
      expect(response.body).to include(metric_b.name)
    end
  end

  describe "POST /runs/:id/regrade" do
    before do
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
      allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    end

    it "re-grades existing responses with the current judge and flashes a regrading notice" do
      run.update!(judge_model: "gpt-4.1")
      metric = metric_group.metrics.first
      CompletionKit::RunMetric.find_or_create_by!(run: run, metric: metric) { |rm| rm.position = 1 }
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = response_with_output.reviews.find_by(metric_id: metric.id)
      review.update!(status: "succeeded", metric_version_id: v1.id)
      response_with_output.update!(status: "succeeded", response_text: "ok")

      post "/completion_kit/runs/#{run.id}/regrade"
      follow_redirect!
      expect(response.body).to include("Re-grading existing responses against the current metrics")
      expect(CompletionKit::JudgeReviewJob).to have_received(:perform_later).with(response_with_output.id, metric.id, run.id)
    end

    it "flashes a nothing-to-regrade alert when the run has no succeeded responses" do
      run.update!(judge_model: "gpt-4.1")
      metric = metric_group.metrics.first
      CompletionKit::RunMetric.find_or_create_by!(run: run, metric: metric) { |rm| rm.position = 1 }
      CompletionKit::MetricVersion.ensure_current_for(metric)
      response_with_output.update!(status: "failed", response_text: nil)
      response_without_expected.update!(status: "failed", response_text: nil)

      post "/completion_kit/runs/#{run.id}/regrade"
      follow_redirect!
      expect(response.body).to include("Nothing to re-grade")
    end
  end

  it "surfaces the stale-versions banner on the run show page with a Re-run with current judge button when a published metric_version supersedes the one a review was scored against" do
    metric = metric_group.metrics.first
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: v1.id)
    v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!
    run.update!(status: "completed")

    get "/completion_kit/runs/#{run.id}"

    expect(response.body).to include("ck-stale-versions-banner")
    expect(response.body).to include("Re-grade with current metrics")
    expect(response.body).to include("Re-run from scratch")
    expect(response.body).to include(metric.name)
  end

  it "hides the stale-versions banner when no reviews are scored against a superseded version" do
    metric = metric_group.metrics.first
    current = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: current.id)
    run.update!(status: "completed")

    get "/completion_kit/runs/#{run.id}"

    expect(response.body).not_to include("ck-stale-versions-banner")
  end

  it "hides the stale-versions banner when the run is not yet completed even if a review is technically stale" do
    metric = metric_group.metrics.first
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: v1.id)
    v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!
    run.update!(status: "running")

    get "/completion_kit/runs/#{run.id}"

    expect(response.body).to include("ck-stale-versions-banner")
    expect(response.body).not_to include("Re-grade with current metrics")
    expect(response.body).not_to include("Re-run from scratch")
  end

  it "shows the source-chip with current styling when the review's metric_version matches the metric's current version" do
    metric = metric_group.metrics.first
    current = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: current.id)

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}"

    expect(response.body).not_to include("ck-review-card--stale")
    expect(response.body).to include("ck-source-chip--current")
    expect(response.body).to include(">v1<")
  end

  it "shows the metric version chip for a judged review" do
    run = create(:completion_kit_run, prompt: prompt)
    response_row = create(:completion_kit_response, run: run)
    metric = create(:completion_kit_metric)
    version = CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_review, response: response_row, metric: metric, metric_version: version, ai_score: 4.0)

    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ck-source-chip")
    expect(response.body).to include(version.version_label)
  end

  it "renders show for a judge-only run (no prompt) without crashing" do
    dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")
    judge_only_run = create(:completion_kit_run, prompt: nil, dataset: dataset, output_column: "actual_output", name: "Judge baseline")
    judge_only_response = create(:completion_kit_response, run: judge_only_run, response_text: "hello", expected_output: nil)

    get "/completion_kit/runs/#{judge_only_run.id}/responses/#{judge_only_response.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Judge baseline")
    expect(response.body).to include("actual_output")
  end

  it "renders show without expected output" do
    get "/completion_kit/runs/#{run.id}/responses/#{response_without_expected.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Expected")
  end

  it "orders responses by score_asc when judge is configured" do
    allow_any_instance_of(CompletionKit::Run).to receive(:judge_configured?).and_return(true)

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}", params: { sort: "score_asc" }
    expect(response).to have_http_status(:ok)
  end

  it "orders responses by score_desc when judge is configured and sort is score_desc" do
    allow_any_instance_of(CompletionKit::Run).to receive(:judge_configured?).and_return(true)

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}", params: { sort: "score_desc" }
    expect(response).to have_http_status(:ok)
  end

  it "orders responses by id when sort is none or judge not configured" do
    allow_any_instance_of(CompletionKit::Run).to receive(:judge_configured?).and_return(false)

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}", params: { sort: "none" }
    expect(response).to have_http_status(:ok)
  end
end
