require "rails_helper"

RSpec.describe CompletionKit::LlmClient, type: :service do
  it "routes provider and model lookups and rejects unknown providers" do
    expect(described_class.for_provider("openai")).to be_a(CompletionKit::OpenAiClient)
    expect(described_class.for_provider("anthropic")).to be_a(CompletionKit::AnthropicClient)
    expect(described_class.for_provider("ollama")).to be_a(CompletionKit::OllamaClient)
    expect(described_class.for_provider("openrouter")).to be_a(CompletionKit::OpenRouterClient)
    expect { described_class.for_provider("unknown") }.to raise_error(ArgumentError, /Unsupported provider/)

    allow(CompletionKit::ApiConfig).to receive(:provider_for_model).with("gpt-4.1").and_return("openai")
    expect(described_class.for_model("gpt-4.1")).to be_a(CompletionKit::OpenAiClient)
    allow(CompletionKit::ApiConfig).to receive(:provider_for_model).with("mystery").and_return(nil)
    expect { described_class.for_model("mystery") }.to raise_error(ArgumentError, /Unsupported model/)
  end

  it "raises for unimplemented instance methods on the base client" do
    client = described_class.new

    expect { client.generate_completion("prompt") }.to raise_error(NotImplementedError)
    expect { client.available_models }.to raise_error(NotImplementedError)
    expect { client.configured? }.to raise_error(NotImplementedError)
    expect(client.configuration_errors).to eq([])
  end
end
