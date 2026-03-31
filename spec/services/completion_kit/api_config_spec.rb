require "rails_helper"

RSpec.describe CompletionKit::ApiConfig, type: :service do
  around do |example|
    original_values = {
      openai: CompletionKit.config.openai_api_key,
      anthropic: CompletionKit.config.anthropic_api_key,
      llama_key: CompletionKit.config.llama_api_key,
      llama_endpoint: CompletionKit.config.llama_api_endpoint
    }

    example.run
  ensure
    CompletionKit.config.openai_api_key = original_values[:openai]
    CompletionKit.config.anthropic_api_key = original_values[:anthropic]
    CompletionKit.config.llama_api_key = original_values[:llama_key]
    CompletionKit.config.llama_api_endpoint = original_values[:llama_endpoint]
  end

  it "returns provider-specific config for supported models and empty config otherwise" do
    CompletionKit.config.openai_api_key = "openai-key"
    CompletionKit.config.anthropic_api_key = "anthropic-key"
    CompletionKit.config.llama_api_key = "llama-key"
    CompletionKit.config.llama_api_endpoint = "https://llama.example.test"

    expect(described_class.for_model("gpt-4.1")).to eq(api_key: "openai-key", provider: "openai")
    expect(described_class.for_model("claude-3-7-sonnet-latest")).to eq(api_key: "anthropic-key", provider: "anthropic")
    expect(described_class.for_model("llama-3.1-8b-instruct")).to eq(api_key: "llama-key", api_endpoint: "https://llama.example.test", provider: "llama")
    expect(described_class.for_model("unknown")).to eq({})
  end

  it "delegates validity and errors to the model-specific client" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true, configuration_errors: ["none"])

    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    expect(described_class.valid_for_model?("gpt-4.1")).to eq(true)
    expect(described_class.errors_for_model("gpt-4.1")).to eq(["none"])

    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test2")
    create(:completion_kit_provider_credential, provider: "llama", api_key: "sk-test3")
    expect(described_class.available_models.map { |model| model[:id] }).to include("gpt-5.4-mini", "claude-3-7-sonnet-latest", "llama-3.1-8b-instruct")
  end

  it "covers provider fallbacks, stored credentials, and rescue branches" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "db-openai")
    client = instance_double(CompletionKit::OpenAiClient, available_models: [{ id: "custom-openai", name: "Custom OpenAI" }])

    allow(CompletionKit::LlmClient).to receive(:for_provider).with("openai", hash_including(api_key: "db-openai")).and_return(client)
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("anthropic", hash_including(provider: "anthropic")).and_raise(StandardError, "down")
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("llama", hash_including(provider: "llama")).and_raise(StandardError, "down")

    expect(described_class.for_provider("unknown")).to eq({})
    expect(described_class.provider_for_model("custom-openai")).to eq("openai")
    expect(described_class.provider_for_model("llama-special")).to eq("llama")
    expect(described_class.provider_for_model("mystery")).to eq(nil)
    expect(described_class.available_models(provider: "openai")).to eq([{ id: "custom-openai", name: "Custom OpenAI", provider: "openai" }])

    allow(described_class).to receive(:available_models).and_return([])
    expect(described_class.provider_for_model("gpt-fallback")).to eq("openai")
    expect(described_class.provider_for_model("claude-fallback")).to eq("anthropic")

    credential.destroy!
  end

  it "returns empty models when no providers are configured" do
    expect(described_class.available_models).to eq([])
  end

  it "skips unconfigured providers when filtering by provider" do
    expect(described_class.available_models(provider: "openai")).to eq([])
  end

  it "rescues errors from configured providers" do
    create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-fail")
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("anthropic", anything).and_raise(StandardError, "API down")
    expect(described_class.available_models).to eq([])
  end
end
