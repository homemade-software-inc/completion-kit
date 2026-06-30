FactoryBot.define do
  factory :completion_kit_metric, class: "CompletionKit::Metric" do
    sequence(:name) { |n| "Helpfulness #{n}" }
    instruction { "Measures whether the output is useful and actionable." }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }

    trait :check do
      sequence(:name) { |n| "Valid JSON #{n}" }
      metric_type { "check" }
      instruction { nil }
      rubric_bands { nil }
      check_config { { "check_kind" => "valid_json", "target" => "response_text" } }
    end
  end
end
