FactoryBot.define do
  factory :completion_kit_metric_group, class: "CompletionKit::MetricGroup" do
    name { "Support QA" }
    description { "Metrics for checking support-oriented responses." }

    trait :with_metrics do
      transient do
        metrics_count { 2 }
      end

      after(:create) do |metric_group, evaluator|
        create_list(:completion_kit_metric_group_membership, evaluator.metrics_count, metric_group: metric_group)
      end
    end
  end
end
