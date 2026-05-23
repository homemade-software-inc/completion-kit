FactoryBot.define do
  factory :completion_kit_calibration, class: "CompletionKit::Calibration" do
    association :run, factory: :completion_kit_run
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    judge_version { CompletionKit::JudgeVersion.ensure_current_for(metric) }
    verdict { "agree" }
    created_by { "operator" }
  end
end
