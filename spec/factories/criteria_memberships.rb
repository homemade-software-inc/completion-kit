FactoryBot.define do
  factory :completion_kit_criteria_membership, class: "CompletionKit::CriteriaMembership" do
    association :criteria, factory: :completion_kit_criteria
    association :metric, factory: :completion_kit_metric
    sequence(:position) { |n| n }
  end
end
