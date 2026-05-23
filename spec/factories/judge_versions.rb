FactoryBot.define do
  factory :completion_kit_judge_version, class: "CompletionKit::JudgeVersion" do
    association :metric, factory: :completion_kit_metric
    instruction { "Measure helpfulness." }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
    current { true }
  end
end
