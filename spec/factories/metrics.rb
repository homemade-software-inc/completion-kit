FactoryBot.define do
  factory :completion_kit_metric, class: "CompletionKit::Metric" do
    sequence(:name) { |n| "Helpfulness #{n}" }
    instruction { "Measures whether the output is useful and actionable." }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
  end
end
