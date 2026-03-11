FactoryBot.define do
  factory :completion_kit_metric, class: "CompletionKit::Metric" do
    sequence(:name) { |n| "Helpfulness #{n}" }
    criteria { "Measures whether the output is useful and actionable." }
    evaluation_steps { [] }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
  end
end
