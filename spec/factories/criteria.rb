FactoryBot.define do
  factory :completion_kit_criteria, class: "CompletionKit::Criteria" do
    name { "Support QA" }
    description { "Metrics for checking support-oriented responses." }

    trait :with_metrics do
      transient do
        metrics_count { 2 }
      end

      after(:create) do |criteria, evaluator|
        create_list(:completion_kit_criteria_membership, evaluator.metrics_count, criteria: criteria)
      end
    end
  end
end
