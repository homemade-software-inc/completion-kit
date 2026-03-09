FactoryBot.define do
  factory :completion_kit_test_result_metric_assessment, class: "CompletionKit::TestResultMetricAssessment" do
    association :test_result, factory: :completion_kit_test_result
    association :metric, factory: :completion_kit_metric
    metric_name { metric.name }
    guidance_text { metric.guidance_text }
    rubric_text { metric.rubric_text }
    status { "evaluated" }
    ai_score { 8.5 }
    ai_feedback { "Strong match for the metric." }
  end
end
