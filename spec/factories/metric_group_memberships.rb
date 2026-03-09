FactoryBot.define do
  factory :completion_kit_metric_group_membership, class: "CompletionKit::MetricGroupMembership" do
    association :metric_group, factory: :completion_kit_metric_group
    association :metric, factory: :completion_kit_metric
    sequence(:position) { |n| n }
  end
end
