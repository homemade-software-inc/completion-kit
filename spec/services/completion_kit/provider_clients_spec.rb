require "rails_helper"
require "faraday"
require "json"

RSpec.describe "CompletionKit provider clients", type: :service do
  def faraday_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def stub_faraday(response)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value)
        self.path = value
      end
    end
    request = request_class.new(headers: {})
    connection = double("Faraday::Connection")

    allow(connection).to receive(:request)
    allow(connection).to receive(:adapter)
    allow(connection).to receive(:options).and_return(Struct.new(:timeout, :open_timeout).new)
    allow(connection).to receive(:post).and_yield(request).and_return(response)
    allow(connection).to receive(:get).and_yield(request).and_return(response)
    allow(Faraday).to receive(:new).and_yield(connection).and_return(connection)

    request
  end

  def faraday_get_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def stub_faraday_get(response)
    request = Struct.new(:headers).new({})
    connection = double("Faraday::Connection")

    allow(connection).to receive(:request)
    allow(connection).to receive(:adapter)
    allow(connection).to receive(:options).and_return(Struct.new(:timeout, :open_timeout).new)
    allow(connection).to receive(:get).and_yield(request).and_return(response)
    allow(Faraday).to receive(:new).and_yield(connection).and_return(connection)
    allow(Faraday).to receive(:get).and_yield(request).and_return(response)

    request
  end

  it "covers OpenAI client success, error, rescue, and configuration branches" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    success_request = stub_faraday(faraday_response(success: true, body: {
      output: [{ type: "message", content: [{ type: "output_text", text: " hello " }] }]
    }.to_json))

    expect(client.generate_completion("prompt", model: "gpt-4.1")).to eq("hello")
    expect(success_request.headers["Authorization"]).to eq("Bearer openai-key")
    expect(success_request.path).to eq("/v1/responses")
    expect(client.configured?).to eq(true)
    expect(client.configuration_errors).to eq([])

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited"))
    expect(client.generate_completion("prompt")).to eq("Error: 429 - rate limited")

    allow(Faraday).to receive(:new).and_raise(StandardError, "network down")
    expect(client.generate_completion("prompt")).to eq("Error: network down")

    unconfigured = CompletionKit::OpenAiClient.new
    allow(unconfigured).to receive(:api_key).and_return(nil)
    expect(unconfigured.generate_completion("prompt")).to eq("Error: API key not configured")
    expect(unconfigured.configured?).to eq(false)
    expect(unconfigured.configuration_errors).to include("OpenAI API key is not configured")
  end

  it "covers OpenAI static model listing" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    expect(client.available_models).to eq(CompletionKit::OpenAiClient::STATIC_MODELS)

    allow(Faraday).to receive(:get).and_raise(StandardError, "boom")
    expect(client.available_models).to eq(CompletionKit::OpenAiClient::STATIC_MODELS)

    unconfigured = CompletionKit::OpenAiClient.new
    allow(unconfigured).to receive(:configured?).and_return(false)
    expect(unconfigured.available_models).to eq(CompletionKit::OpenAiClient::STATIC_MODELS)
  end

  it "covers Anthropic client success, error, rescue, and configuration branches" do
    client = CompletionKit::AnthropicClient.new(api_key: "anthropic-key")
    success_request = stub_faraday(faraday_response(success: true, body: { content: [{ text: " hello " }] }.to_json))

    expect(client.generate_completion("prompt", model: "claude-3-7-sonnet-latest")).to eq("hello")
    expect(success_request.headers["x-api-key"]).to eq("anthropic-key")
    expect(client.available_models).to include(hash_including(id: "claude-3-7-sonnet-latest"))
    expect(client.configured?).to eq(true)
    expect(client.configuration_errors).to eq([])

    stub_faraday(faraday_response(success: false, status: 400, body: "bad request"))
    expect(client.generate_completion("prompt")).to eq("Error: 400 - bad request")

    allow(Faraday).to receive(:new).and_raise(StandardError, "anthropic down")
    expect(client.generate_completion("prompt")).to eq("Error: anthropic down")

    unconfigured = CompletionKit::AnthropicClient.new
    expect(unconfigured.generate_completion("prompt")).to eq("Error: API key not configured")
    expect(unconfigured.configured?).to eq(false)
    expect(unconfigured.configuration_errors).to include("Anthropic API key is not configured")
    expect(unconfigured.available_models).to eq(CompletionKit::AnthropicClient::STATIC_MODELS)
  end

  it "covers Anthropic dynamic model listing branches" do
    client = CompletionKit::AnthropicClient.new(api_key: "anthropic-key")

    stub_faraday_get(faraday_get_response(success: true, body: { data: [{ id: "claude-3-7-sonnet-latest" }] }.to_json))
    expect(client.available_models).to eq([{ id: "claude-3-7-sonnet-latest", name: "claude-3-7-sonnet-latest" }])

    stub_faraday_get(faraday_get_response(success: false, body: "nope", status: 500))
    expect(client.available_models).to eq(CompletionKit::AnthropicClient::STATIC_MODELS)

    allow(Faraday).to receive(:new).and_raise(StandardError, "boom")
    expect(client.available_models).to eq(CompletionKit::AnthropicClient::STATIC_MODELS)
  end

  it "covers Ollama client success, error, rescue, and configuration branches" do
    client = CompletionKit::OllamaClient.new(api_key: "ollama-key", api_endpoint: "https://ollama.example.test")
    success_request = stub_faraday(faraday_response(success: true, body: { choices: [{ text: " hello " }] }.to_json))

    expect(client.generate_completion("prompt", model: "llama3.3")).to eq("hello")
    expect(success_request.headers["Authorization"]).to eq("Bearer ollama-key")
    expect(client.configured?).to eq(true)
    expect(client.configuration_errors).to eq([])

    stub_faraday(faraday_response(success: false, status: 500, body: "broken"))
    expect(client.generate_completion("prompt")).to eq("Error: 500 - broken")

    allow(Faraday).to receive(:new).and_raise(StandardError, "ollama down")
    expect(client.generate_completion("prompt")).to eq("Error: ollama down")

    no_key = CompletionKit::OllamaClient.new(api_endpoint: "https://ollama.example.test")
    request = stub_faraday(faraday_response(success: true, body: { choices: [{ text: "ok" }] }.to_json))
    expect(no_key.generate_completion("prompt")).to eq("ok")
    expect(request.headers["Authorization"]).to be_nil

    missing_endpoint = CompletionKit::OllamaClient.new(api_key: "ollama-key", api_endpoint: nil)
    allow(missing_endpoint).to receive(:api_endpoint).and_return(nil)
    expect(missing_endpoint.configured?).to eq(false)
    expect(missing_endpoint.configuration_errors).to include("Ollama API endpoint is not configured")
    expect(missing_endpoint.generate_completion("prompt")).to eq("Error: API endpoint not configured")
    expect(missing_endpoint.available_models).to eq([])
  end

  it "covers Ollama dynamic model listing branches" do
    client = CompletionKit::OllamaClient.new(api_key: "ollama-key", api_endpoint: "https://ollama.example.test")

    request = stub_faraday_get(faraday_get_response(success: true, body: { data: [{ id: "llama3.3" }] }.to_json))
    expect(client.available_models).to eq([{ id: "llama3.3", name: "llama3.3" }])
    expect(request.headers["Authorization"]).to eq("Bearer ollama-key")

    stub_faraday_get(faraday_get_response(success: false, body: "nope", status: 500))
    expect(client.available_models).to eq([])

    allow(Faraday).to receive(:new).and_raise(StandardError, "boom")
    expect(client.available_models).to eq([])

    no_key_client = CompletionKit::OllamaClient.new(api_endpoint: "https://ollama.example.test")
    request = stub_faraday_get(faraday_get_response(success: true, body: { data: [{ id: "qwen2.5" }] }.to_json))
    expect(no_key_client.available_models).to eq([{ id: "qwen2.5", name: "qwen2.5" }])
    expect(request.headers["Authorization"]).to be_nil
  end
end
