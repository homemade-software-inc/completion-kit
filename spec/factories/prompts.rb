FactoryBot.define do
  factory :completion_kit_prompt, class: "CompletionKit::Prompt" do
    name { "Summarizer" }
    description { "Summarizes a source passage" }
    template { "Summarize {{content}} for {{audience}}" }
    llm_model { "gpt-4.1" }
    assessment_model { "gpt-4o-mini" }
    family_key { SecureRandom.uuid }
    version_number { 1 }
    current { true }
    review_guidance { "Prefer concise, accurate summaries." }
    rubric_text { CompletionKit::Metric.default_rubric_text }
    rubric_bands { CompletionKit::Metric.default_rubric_bands }
    published_at { Time.current }
  end
end
