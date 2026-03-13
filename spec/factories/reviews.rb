FactoryBot.define do
  factory :completion_kit_review, class: "CompletionKit::Review" do
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_name { metric.name }
    status { "evaluated" }
    ai_score { 4.5 }
    ai_feedback { "Strong match for the metric." }
  end
end
