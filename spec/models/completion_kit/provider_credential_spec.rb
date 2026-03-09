require "rails_helper"

RSpec.describe CompletionKit::ProviderCredential, type: :model do
  it "returns config data and delegates to the provider client" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "secret")
    client = instance_double(CompletionKit::OpenAiClient, available_models: [{ id: "gpt-4.1" }], configured?: true)

    allow(CompletionKit::LlmClient).to receive(:for_provider).with("openai", hash_including(api_key: "secret", provider: "openai")).and_return(client)

    expect(credential.config_hash).to eq(provider: "openai", api_key: "secret")
    expect(credential.available_models).to eq([{ id: "gpt-4.1" }])
    expect(credential.configured?).to eq(true)
  end

  it "returns safe defaults when the client raises" do
    credential = create(:completion_kit_provider_credential, provider: "anthropic", api_key: "secret")

    allow(CompletionKit::LlmClient).to receive(:for_provider).and_raise(StandardError, "boom")

    expect(credential.available_models).to eq([])
    expect(credential.configured?).to eq(false)
  end
end
