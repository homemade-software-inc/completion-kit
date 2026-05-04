FactoryBot.define do
  factory :completion_kit_review, class: "CompletionKit::Review" do
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_name { "Quality" }
    instruction { "Rate the response quality." }
    status { "succeeded" }
    ai_score { 4.0 }
    ai_feedback { "Good response." }
  end
end
