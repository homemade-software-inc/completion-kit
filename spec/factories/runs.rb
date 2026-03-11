FactoryBot.define do
  factory :completion_kit_run, class: "CompletionKit::Run" do
    association :prompt, factory: :completion_kit_prompt
    association :dataset, factory: :completion_kit_dataset
    name { "Test run" }
    status { "pending" }
  end
end
