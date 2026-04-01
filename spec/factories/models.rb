FactoryBot.define do
  factory :completion_kit_model, class: "CompletionKit::Model" do
    provider { "openai" }
    sequence(:model_id) { |n| "gpt-#{n}" }
    status { "active" }
    supports_generation { true }
    supports_judging { true }
  end
end
