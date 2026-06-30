FactoryBot.define do
  factory :completion_kit_review, class: "CompletionKit::Review" do
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_version { metric&.persisted? ? CompletionKit::MetricVersion.ensure_current_for(metric) : nil }
    metric_name { "Quality" }
    instruction { "Rate the response quality." }
    status { "succeeded" }
    ai_score { 4.0 }
    ai_feedback { "Good response." }

    trait :check do
      association :metric, factory: [:completion_kit_metric, :check]
      metric_name { "Valid JSON" }
      instruction { nil }
      ai_score { nil }
      passed { true }
    end
  end
end
