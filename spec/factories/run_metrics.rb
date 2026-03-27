FactoryBot.define do
  factory :completion_kit_run_metric, class: "CompletionKit::RunMetric" do
    association :run, factory: :completion_kit_run
    association :metric, factory: :completion_kit_metric
    sequence(:position) { |n| n }
  end
end
