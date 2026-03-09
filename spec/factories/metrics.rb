FactoryBot.define do
  factory :completion_kit_metric, class: "CompletionKit::Metric" do
    name { "Helpfulness" }
    description { "Measures whether the output is useful and actionable." }
    guidance_text { "Reward direct usefulness, task completion, and clear next steps." }
    rubric_text { CompletionKit::Metric.default_rubric_text }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
  end
end
