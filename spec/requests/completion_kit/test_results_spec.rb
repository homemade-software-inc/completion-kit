require "rails_helper"

RSpec.describe "CompletionKit test results", type: :request do
  let!(:metric_group) { create(:completion_kit_metric_group, :with_metrics) }
  let!(:prompt) { create(:completion_kit_prompt, metric_group: metric_group) }
  let!(:test_run) { create(:completion_kit_test_run, prompt: prompt, name: "Run Results") }
  let!(:high_result) { create(:completion_kit_test_result, test_run: test_run, quality_score: 9.0, output_text: "alpha beta", expected_output: "alpha beta") }
  let!(:medium_result) { create(:completion_kit_test_result, test_run: test_run, quality_score: 6.0, output_text: "beta gamma", expected_output: "beta") }
  let!(:low_result) { create(:completion_kit_test_result, test_run: test_run, quality_score: 1.0, output_text: "delta", expected_output: "epsilon") }
  let!(:pending_result) { create(:completion_kit_test_result, test_run: test_run, quality_score: nil, expected_output: nil) }

  before do
    metric_group.metrics.each do |metric|
      create(:completion_kit_test_result_metric_assessment, test_result: high_result, metric: metric, metric_name: metric.name, ai_score: 8.5, ai_feedback: "Solid #{metric.name}")
    end
  end

  it "renders index across sort and filter branches" do
    %w[score_desc score_asc created_desc created_asc weird].each do |sort|
      get "/completion_kit/test_runs/#{test_run.id}/test_results", params: { sort: sort }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Run Results")
    end

    %w[all high_quality medium_quality low_quality no_score].each do |filter|
      get "/completion_kit/test_runs/#{test_run.id}/test_results", params: { filter: filter }
      expect(response).to have_http_status(:ok)
    end
  end

  it "renders show with comparison details and per-metric review" do
    get "/completion_kit/test_runs/#{test_run.id}/test_results/#{high_result.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Word overlap")
    expect(response.body).to include("Human review")
    expect(response.body).to include(metric_group.metrics.first.name)
  end

  it "renders show without comparison details when expected output is absent" do
    get "/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Word-overlap match")
  end

  it "saves a human review and handles invalid review input" do
    assessment = create(:completion_kit_test_result_metric_assessment, test_result: pending_result, metric: metric_group.metrics.first, metric_name: metric_group.metrics.first.name, human_score: nil, human_feedback: nil, human_reviewer_name: nil, human_reviewed_at: nil)

    patch "/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}/human_review",
      params: {
        test_result: {
          metric_assessments_attributes: {
            "0" => {
              id: assessment.id,
              metric_id: assessment.metric_id,
              metric_name: assessment.metric_name,
              human_reviewer_name: "Dana",
              human_score: 7.5,
              human_feedback: "Good enough"
            }
          }
        }
      }

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}")
    expect(assessment.reload.human_score.to_f).to eq(7.5)

    patch "/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}/human_review",
      params: {
        test_result: {
          metric_assessments_attributes: {
            "0" => {
              id: assessment.id,
              metric_id: assessment.metric_id,
              metric_name: assessment.metric_name,
              human_reviewer_name: "Dana",
              human_score: 11,
              human_feedback: "Bad"
            }
          }
        }
      }

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}")
    expect(flash[:alert]).to be_present
  end

  it "handles empty human review payloads" do
    patch "/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}/human_review",
      params: { test_result: {} }

    expect(response).to redirect_to("/completion_kit/test_runs/#{test_run.id}/test_results/#{pending_result.id}")
  end
end
