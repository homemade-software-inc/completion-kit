FactoryBot.define do
  factory :completion_kit_tagging, class: "CompletionKit::Tagging" do
    association :tag, factory: :completion_kit_tag
    association :taggable, factory: :completion_kit_metric
  end
end
