FactoryBot.define do
  factory :completion_kit_prompt, class: "CompletionKit::Prompt" do
    name { "Summarizer" }
    description { "Summarizes a source passage" }
    template { "Summarize {{content}} for {{audience}}" }
    llm_model do
      CompletionKit::Model.find_or_create_by!(
        provider: "openai",
        model_id: "gpt-4.1-mini"
      ) do |m|
        m.assign_attributes(
          status: "active",
          supports_generation: true,
          supports_judging: true
        )
      end.model_id
    end
    family_key { SecureRandom.uuid }
    version_number { 1 }
    current { true }
    published_at { Time.current }

    trait :with_provider_credential do
      after(:build) do |_prompt|
        unless CompletionKit::ProviderCredential.exists?(provider: "openai")
          allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
          CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key")
        end
      end
    end
  end
end
