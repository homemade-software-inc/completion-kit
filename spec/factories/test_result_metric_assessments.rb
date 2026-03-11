FactoryBot.define do
  factory :completion_kit_test_result_metric_assessment, class: "CompletionKit::TestResultMetricAssessment" do
    association :test_result, factory: :completion_kit_test_result
    association :metric, factory: :completion_kit_metric
    metric_name { metric.name }
    criteria { metric.criteria }
    rubric_text { metric.display_rubric_text }
    status { "evaluated" }
    ai_score { 4.5 }
    ai_feedback { "Strong match for the metric." }
  end
end
