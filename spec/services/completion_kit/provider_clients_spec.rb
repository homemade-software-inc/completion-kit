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
    builder = instance_double("Faraday::RackBuilder")
    connection = instance_double("Faraday::Connection")

    allow(builder).to receive(:request)
    allow(builder).to receive(:adapter)
    allow(connection).to receive(:post).and_yield(request).and_return(response)
    allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)

    request
  end

  def faraday_get_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def stub_faraday_get(response)
    request = Struct.new(:headers).new({})
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

    allow(Faraday).to receive(:get).and_raise(StandardError, "boom")
    expect(client.available_models).to eq(CompletionKit::AnthropicClient::STATIC_MODELS)
  end

  it "covers Llama client success, error, rescue, and configuration branches" do
    client = CompletionKit::LlamaClient.new(api_key: "llama-key", api_endpoint: "https://llama.example.test")
    success_request = stub_faraday(faraday_response(success: true, body: { choices: [{ text: " hello " }] }.to_json))

    expect(client.generate_completion("prompt", model: "llama-3.1-8b-instruct")).to eq("hello")
    expect(success_request.headers["Authorization"]).to eq("Bearer llama-key")
    expect(client.available_models).to eq([{ id: "llama-3.1-8b-instruct", name: "Llama 3.1 8B Instruct" }, { id: "llama-3.1-70b-instruct", name: "Llama 3.1 70B Instruct" }])
    expect(client.configured?).to eq(true)
    expect(client.configuration_errors).to eq([])

    stub_faraday(faraday_response(success: false, status: 500, body: "broken"))
    expect(client.generate_completion("prompt")).to eq("Error: 500 - broken")

    allow(Faraday).to receive(:new).and_raise(StandardError, "llama down")
    expect(client.generate_completion("prompt")).to eq("Error: llama down")

    missing_endpoint = CompletionKit::LlamaClient.new(api_key: "llama-key", api_endpoint: nil)
    allow(missing_endpoint).to receive(:api_endpoint).and_return(nil)
    expect(missing_endpoint.configured?).to eq(false)
    expect(missing_endpoint.configuration_errors).to include("Llama API endpoint is not configured")

    missing_key = CompletionKit::LlamaClient.new(api_endpoint: nil)
    allow(missing_key).to receive(:api_key).and_return(nil)
    allow(missing_key).to receive(:api_endpoint).and_return(nil)
    expect(missing_key.generate_completion("prompt")).to eq("Error: API credentials not configured")
    expect(missing_key.configuration_errors).to include("Llama API key is not configured")
    expect(missing_key.available_models).to eq(CompletionKit::LlamaClient::STATIC_MODELS)
  end

  it "covers Llama dynamic model listing branches" do
    client = CompletionKit::LlamaClient.new(api_key: "llama-key", api_endpoint: "https://llama.example.test")

    request = stub_faraday_get(faraday_get_response(success: true, body: { data: [{ id: "llama-custom" }] }.to_json))
    expect(client.available_models).to eq([{ id: "llama-custom", name: "llama-custom" }])
    expect(request.headers["Authorization"]).to eq("Bearer llama-key")

    stub_faraday_get(faraday_get_response(success: false, body: "nope", status: 500))
    expect(client.available_models).to eq(CompletionKit::LlamaClient::STATIC_MODELS)

    allow(Faraday).to receive(:get).and_raise(StandardError, "boom")
    expect(client.available_models).to eq(CompletionKit::LlamaClient::STATIC_MODELS)

    missing_key = CompletionKit::LlamaClient.new(api_key: "llama-key", api_endpoint: "https://llama.example.test")
    allow(missing_key).to receive(:configured?).and_return(true)
    allow(missing_key).to receive(:api_key).and_return(nil)
    request = stub_faraday_get(faraday_get_response(success: true, body: { data: [] }.to_json))
    expect(missing_key.available_models).to eq(CompletionKit::LlamaClient::STATIC_MODELS)
    expect(request.headers["Authorization"]).to be_nil
  end
end
