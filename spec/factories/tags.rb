FactoryBot.define do
  factory :completion_kit_tag, class: "CompletionKit::Tag" do
    sequence(:name) { |n| "tag-#{n}" }
  end
end
