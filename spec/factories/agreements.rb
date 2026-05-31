FactoryBot.define do
  factory :completion_kit_agreement, class: "CompletionKit::Agreement" do
    association :run, factory: :completion_kit_run
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_version { CompletionKit::MetricVersion.ensure_current_for(metric) }
    verdict { "agree" }
    created_by { "operator" }
  end
end
