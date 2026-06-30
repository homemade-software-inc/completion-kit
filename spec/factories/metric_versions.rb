FactoryBot.define do
  factory :completion_kit_metric_version, class: "CompletionKit::MetricVersion" do
    association :metric, factory: :completion_kit_metric
    instruction { "Measure helpfulness." }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
    current { true }

    trait :check do
      association :metric, factory: [:completion_kit_metric, :check]
      metric_type { "check" }
      instruction { nil }
      rubric_bands { nil }
      check_config { { "check_kind" => "valid_json", "target" => "response_text" } }
    end
  end
end
