require "rails_helper"
require "faraday"
require "json"

RSpec.describe "CompletionKit provider clients", type: :service do
  def faraday_response(success:, body:, status: 200, headers: {})
    instance_double("Faraday::Response", success?: success, body: body, status: status, headers: headers)
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

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited", headers: { "Retry-After" => "30" }))
    expect { client.generate_completion("prompt") }.to raise_error(CompletionKit::RateLimitError) do |error|
      expect(error.provider).to eq("openai")
      expect(error.status).to eq(429)
      expect(error.retry_after).to eq(30)
    end

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited", headers: {}))
    expect { client.generate_completion("prompt") }.to raise_error(CompletionKit::RateLimitError) do |error|
      expect(error.retry_after).to be_nil
    end

    stub_faraday(faraday_response(success: false, status: 500, body: "broken", headers: {}))
    expect(client.generate_completion("prompt")).to eq("Error: 500 - broken")

    allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, "connection refused")
    expect { client.generate_completion("prompt") }.to raise_error(Faraday::ConnectionFailed)

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

    stub_faraday(faraday_response(success: false, status: 400, body: "bad request", headers: {}))
    expect(client.generate_completion("prompt")).to eq("Error: 400 - bad request")

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited", headers: {}))
    expect { client.generate_completion("prompt") }.to raise_error(CompletionKit::RateLimitError) do |error|
      expect(error.provider).to eq("anthropic")
      expect(error.status).to eq(429)
      expect(error.retry_after).to be_nil
    end

    allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, "connection refused")
    expect { client.generate_completion("prompt") }.to raise_error(Faraday::ConnectionFailed)

    allow(Faraday).to receive(:new).and_raise(StandardError, "anthropic down")
    expect(client.generate_completion("prompt")).to eq("Error: anthropic down")

    unconfigured = CompletionKit::AnthropicClient.new
    expect(unconfigured.generate_completion("prompt")).to eq("Error: API key not configured")
    expect(unconfigured.configured?).to eq(false)
    expect(unconfigured.configuration_errors).to include("Anthropic API key is not configured")
    expect(unconfigured.available_models).to eq(CompletionKit::AnthropicClient::STATIC_MODELS)
  end

  def stub_temperature_fallback(deprecated_body:, success_body:)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value); self.path = value; end
    end
    posted = []
    connection = double("Faraday::Connection")
    allow(connection).to receive(:request)
    allow(connection).to receive(:adapter)
    allow(connection).to receive(:options).and_return(Struct.new(:timeout, :open_timeout).new)
    allow(connection).to receive(:post) do |&block|
      req = request_class.new(headers: {})
      block&.call(req)
      posted << req
      if posted.length == 1
        faraday_response(success: false, status: 400, body: deprecated_body, headers: {})
      else
        faraday_response(success: true, body: success_body, status: 200, headers: {})
      end
    end
    allow(Faraday).to receive(:new).and_yield(connection).and_return(connection)
    posted
  end

  it "retries Anthropic request without temperature when the model rejects it" do
    client = CompletionKit::AnthropicClient.new(api_key: "anthropic-key")
    posted = stub_temperature_fallback(
      deprecated_body: { type: "error", error: { type: "invalid_request_error", message: "`temperature` is deprecated for this model." } }.to_json,
      success_body: { content: [{ text: "no-temp result" }] }.to_json
    )

    expect(client.generate_completion("prompt", model: "claude-opus-4-7", temperature: 0.7)).to eq("no-temp result")
    expect(posted[0].body).to include("\"temperature\":0.7")
    expect(posted[1].body).not_to include("temperature")
    expect(client.temperature_dropped?).to be(true)
  end

  it "exposes temperature_dropped? as false on each provider client when the request succeeds with temperature" do
    [
      [CompletionKit::AnthropicClient.new(api_key: "k"), { content: [{ text: "hi" }] }.to_json],
      [CompletionKit::OpenAiClient.new(api_key: "k"), { output: [{ type: "message", content: [{ type: "output_text", text: "hi" }] }] }.to_json],
      [CompletionKit::OpenRouterClient.new(api_key: "k"), { choices: [{ message: { content: "hi" } }] }.to_json],
      [CompletionKit::OllamaClient.new(api_key: "k", api_endpoint: "https://ollama.example.test"), { choices: [{ text: "hi" }] }.to_json]
    ].each do |client, body|
      stub_faraday(faraday_response(success: true, body: body))
      client.generate_completion("prompt", temperature: 0.5)
      expect(client.temperature_dropped?).to be(false), "expected #{client.class} temperature_dropped? to be false"
    end
  end

  it "returns an error when OpenAI response output has no message item (reasoning model ate the budget)" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    stub_faraday(faraday_response(success: true, body: { output: [{ type: "reasoning" }] }.to_json))

    expect(client.generate_completion("prompt", model: "o1-preview")).to eq("Error: model returned empty content")
  end

  it "returns an error when OpenAI marks the response as incomplete due to max_output_tokens" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    stub_faraday(faraday_response(success: true, body: {
      status: "incomplete",
      incomplete_details: { reason: "max_output_tokens" },
      output: []
    }.to_json))

    result = client.generate_completion("prompt", model: "gpt-5.5-pro")
    expect(result).to start_with("Error: response incomplete (max_output_tokens)")
  end

  it "falls back to a generic incomplete reason when OpenAI omits incomplete_details" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    stub_faraday(faraday_response(success: true, body: { status: "incomplete", output: [] }.to_json))

    expect(client.generate_completion("prompt")).to start_with("Error: response incomplete (unknown)")
  end

  it "retries OpenAI request without temperature when the model rejects it" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    posted = stub_temperature_fallback(
      deprecated_body: { error: { message: "Unsupported parameter: 'temperature' is not supported with this model." } }.to_json,
      success_body: { output: [{ type: "message", content: [{ type: "output_text", text: "ok" }] }] }.to_json
    )

    expect(client.generate_completion("prompt", model: "gpt-5.5", temperature: 0.5)).to eq("ok")
    expect(posted[0].body).to include("\"temperature\":0.5")
    expect(posted[1].body).not_to include("temperature")
  end

  it "retries OpenRouter request without temperature when upstream rejects it" do
    client = CompletionKit::OpenRouterClient.new(api_key: "or-key")
    posted = stub_temperature_fallback(
      deprecated_body: { error: { message: "`temperature` is deprecated for this model." } }.to_json,
      success_body: { choices: [{ message: { content: "ok" } }] }.to_json
    )

    expect(client.generate_completion("prompt", model: "anthropic/claude-opus-4-7", temperature: 0.7)).to eq("ok")
    expect(posted[0].body).to include("\"temperature\":0.7")
    expect(posted[1].body).not_to include("temperature")
  end

  it "retries Ollama request without temperature when the model rejects it" do
    client = CompletionKit::OllamaClient.new(api_key: "ol-key", api_endpoint: "https://ollama.example.test")
    posted = stub_temperature_fallback(
      deprecated_body: { error: { message: "temperature is not supported by this model" } }.to_json,
      success_body: { choices: [{ text: "ok" }] }.to_json
    )

    expect(client.generate_completion("prompt", model: "some-model", temperature: 0.5)).to eq("ok")
    expect(posted[0].body).to include("\"temperature\":0.5")
    expect(posted[1].body).not_to include("temperature")
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

    stub_faraday(faraday_response(success: false, status: 500, body: "broken", headers: {}))
    expect(client.generate_completion("prompt")).to eq("Error: 500 - broken")

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited", headers: {}))
    expect { client.generate_completion("prompt") }.to raise_error(CompletionKit::RateLimitError) do |error|
      expect(error.provider).to eq("ollama")
      expect(error.status).to eq(429)
      expect(error.retry_after).to be_nil
    end

    allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, "connection refused")
    expect { client.generate_completion("prompt") }.to raise_error(Faraday::ConnectionFailed)

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

  it "refuses to call out when the configured endpoint resolves to a private address" do
    client = CompletionKit::OllamaClient.new(api_endpoint: "http://10.0.0.5:11434")
    expect(client.generate_completion("prompt")).to eq("Error: API endpoint resolves to a private address")
    expect(client.available_models).to eq([])
  end

  it "treats a blank endpoint as not configured when allow_loopback_endpoints is false" do
    original = CompletionKit.config.allow_loopback_endpoints
    CompletionKit.config.allow_loopback_endpoints = false
    client = CompletionKit::OllamaClient.new
    expect(client.configured?).to eq(false)
    expect(client.generate_completion("prompt")).to eq("Error: API endpoint not configured")
  ensure
    CompletionKit.config.allow_loopback_endpoints = original
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
