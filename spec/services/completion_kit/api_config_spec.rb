require "rails_helper"

RSpec.describe CompletionKit::ApiConfig, type: :service do
  around do |example|
    original_values = {
      openai: CompletionKit.config.openai_api_key,
      anthropic: CompletionKit.config.anthropic_api_key,
      ollama_key: CompletionKit.config.ollama_api_key,
      ollama_endpoint: CompletionKit.config.ollama_api_endpoint
    }

    example.run
  ensure
    CompletionKit.config.openai_api_key = original_values[:openai]
    CompletionKit.config.anthropic_api_key = original_values[:anthropic]
    CompletionKit.config.ollama_api_key = original_values[:ollama_key]
    CompletionKit.config.ollama_api_endpoint = original_values[:ollama_endpoint]
  end

  it "returns provider-specific config for supported models and empty config otherwise" do
    CompletionKit.config.openai_api_key = "openai-key"
    CompletionKit.config.anthropic_api_key = "anthropic-key"
    CompletionKit.config.ollama_api_key = "ollama-key"
    CompletionKit.config.ollama_api_endpoint = "https://ollama.example.test"

    expect(described_class.for_model("gpt-4.1")).to eq(api_key: "openai-key", provider: "openai")
    expect(described_class.for_model("claude-3-7-sonnet-latest")).to eq(api_key: "anthropic-key", provider: "anthropic")
    expect(described_class.for_provider("ollama")).to eq(api_key: "ollama-key", api_endpoint: "https://ollama.example.test", provider: "ollama")
    expect(described_class.for_model("unknown")).to eq({})
  end

  it "returns openrouter config from ENV" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENROUTER_API_KEY").and_return("or-env-key")
    expect(described_class.for_provider("openrouter")).to eq(api_key: "or-env-key", provider: "openrouter")
  end

  it "delegates validity and errors to the model-specific client" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true, configuration_errors: ["none"])

    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    expect(described_class.valid_for_model?("gpt-4.1")).to eq(true)
    expect(described_class.errors_for_model("gpt-4.1")).to eq(["none"])

    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test2")
    create(:completion_kit_provider_credential, provider: "ollama", api_key: "sk-test3")
    ollama_client = instance_double(CompletionKit::OllamaClient, available_models: [{ id: "llama3.3", name: "llama3.3" }])
    allow(CompletionKit::LlmClient).to receive(:for_provider).and_call_original
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("ollama", hash_including(provider: "ollama")).and_return(ollama_client)
    expect(described_class.available_models.map { |model| model[:id] }).to include("gpt-5.4-mini", "claude-3-7-sonnet-latest", "llama3.3")
  end

  it "covers provider fallbacks, stored credentials, and rescue branches" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "db-openai")
    client = instance_double(CompletionKit::OpenAiClient, available_models: [{ id: "custom-openai", name: "Custom OpenAI" }])

    allow(CompletionKit::LlmClient).to receive(:for_provider).with("openai", hash_including(api_key: "db-openai")).and_return(client)
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("anthropic", hash_including(provider: "anthropic")).and_raise(StandardError, "down")
    allow(CompletionKit::LlmClient).to receive(:for_provider).with("ollama", hash_including(provider: "ollama")).and_raise(StandardError, "down")

    expect(described_class.for_provider("unknown")).to eq({})
    expect(described_class.provider_for_model("custom-openai")).to eq("openai")
    expect(described_class.provider_for_model("mystery")).to eq(nil)
    expect(described_class.available_models(provider: "openai")).to eq([{ id: "custom-openai", name: "Custom OpenAI", provider: "openai" }])

    allow(described_class).to receive(:available_models).and_return([])
    expect(described_class.provider_for_model("gpt-fallback")).to eq("openai")
    expect(described_class.provider_for_model("claude-fallback")).to eq("anthropic")

    credential.destroy!
  end

  it "reads from Model registry when models exist" do
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4o", display_name: "GPT-4o", supports_generation: true, supports_judging: false)
    create(:completion_kit_model, provider: "anthropic", model_id: "claude-3", display_name: "Claude 3", supports_generation: false, supports_judging: true)

    gen = described_class.available_models(scope: :generation)
    expect(gen.map { |m| m[:id] }).to eq(["gpt-4o"])
    expect(gen.first[:name]).to eq("GPT-4o")

    judge = described_class.available_models(scope: :judging)
    expect(judge.map { |m| m[:id] }).to eq(["claude-3"])

    all = described_class.available_models(scope: :all)
    expect(all.length).to eq(2)

    filtered = described_class.available_models(provider: "openai", scope: :generation)
    expect(filtered.map { |m| m[:id] }).to eq(["gpt-4o"])
  end

  it "falls back to display_name or model_id for name" do
    create(:completion_kit_model, provider: "openai", model_id: "gpt-bare", display_name: nil, supports_generation: true)
    result = described_class.available_models(scope: :generation)
    expect(result.first[:name]).to eq("gpt-bare")
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
