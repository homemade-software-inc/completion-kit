FactoryBot.define do
  factory :completion_kit_provider_credential, class: "CompletionKit::ProviderCredential" do
    provider { "openai" }
    api_key { "test-key" }
    api_endpoint { nil }
  end
end
