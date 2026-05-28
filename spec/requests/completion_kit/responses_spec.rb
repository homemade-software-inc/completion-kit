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

  it "marks a review as stale and shows the source-chip v-label when the review's metric_version is no longer current" do
    metric = metric_group.metrics.first
    v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
    review = response_with_output.reviews.find_by(metric_id: metric.id)
    review.update!(metric_version_id: v1.id)
    v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    v2.publish!

    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}"

    expect(response.body).to include("ck-review-card--stale")
    expect(response.body).to include("Scored against a superseded version")
    expect(response.body).to include("ck-source-chip--past")
    expect(response.body).to include(">v1<")
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
