FactoryBot.define do
  factory :completion_kit_prompt, class: "CompletionKit::Prompt" do
    name { "Summarizer" }
    description { "Summarizes a source passage" }
    template { "Summarize {{content}} for {{audience}}" }
    llm_model { "gpt-4.1" }
    family_key { SecureRandom.uuid }
    version_number { 1 }
    current { true }
    published_at { Time.current }
  end
end
