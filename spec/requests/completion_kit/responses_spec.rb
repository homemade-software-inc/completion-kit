require "rails_helper"

RSpec.describe "CompletionKit responses", type: :request do
  let!(:criteria) { create(:completion_kit_criteria, :with_metrics) }
  let!(:prompt) { create(:completion_kit_prompt) }
  let!(:run) { create(:completion_kit_run, prompt: prompt, name: "Run Results") }
  let!(:response_with_output) { create(:completion_kit_response, run: run, response_text: "alpha beta", expected_output: "alpha beta") }
  let!(:response_without_expected) { create(:completion_kit_response, run: run, response_text: "delta", expected_output: nil) }

  before do
    criteria.metrics.each do |metric|
      create(:completion_kit_review, response: response_with_output, metric: metric, metric_name: metric.name, ai_score: 4.5, ai_feedback: "Solid #{metric.name}")
    end
  end

  it "renders show with reviews" do
    get "/completion_kit/runs/#{run.id}/responses/#{response_with_output.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Response")
    expect(response.body).to include(criteria.metrics.first.name)
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
