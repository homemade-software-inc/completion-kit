require "rails_helper"

RSpec.describe "Metric review-grounded examples", type: :request do
  around do |example|
    original = CompletionKit.config.judge_examples_from_reviews
    CompletionKit.config.judge_examples_from_reviews = true
    example.run
  ensure
    CompletionKit.config.judge_examples_from_reviews = original
  end

  let(:metric) { create(:completion_kit_metric) }

  def disagreement(metric)
    response = create(:completion_kit_response)
    create(:completion_kit_review, response: response, metric: metric, ai_score: 4.0)
    create(:completion_kit_calibration,
           metric: metric, response: response, run: response.run,
           verdict: "disagree", corrected_score: 2.0, note: "too high")
  end

  it "mutes a case and removes it from the guiding set" do
    cal = disagreement(metric)
    expect(CompletionKit::MetricCalibrationExamples.judge_examples_for(metric).size).to eq(1)

    post "/completion_kit/metrics/#{metric.id}/exclude_example", params: { calibration_id: cal.id }

    expect(response).to have_http_status(:ok)
    expect(cal.reload.excluded_from_examples).to eq(true)
    expect(CompletionKit::MetricCalibrationExamples.judge_examples_for(metric)).to eq([])
  end

  it "returns not found when the feature flag is off" do
    cal = disagreement(metric)
    CompletionKit.config.judge_examples_from_reviews = false

    post "/completion_kit/metrics/#{metric.id}/exclude_example", params: { calibration_id: cal.id }

    expect(response).to have_http_status(:not_found)
    expect(cal.reload.excluded_from_examples).to eq(false)
  end

  it "shows the guiding section with active cases on the metric page" do
    disagreement(metric)
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).to include("ck-guiding-#{metric.id}")
    expect(response.body).to include("guiding the judge")
  end

  it "hides the guiding section when the flag is off" do
    CompletionKit.config.judge_examples_from_reviews = false
    disagreement(metric)
    get "/completion_kit/metrics/#{metric.id}"
    expect(response.body).not_to include("guiding the judge")
  end
end
