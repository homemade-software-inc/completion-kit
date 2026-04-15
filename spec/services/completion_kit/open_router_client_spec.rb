require "rails_helper"
require "faraday"
require "json"

RSpec.describe CompletionKit::OpenRouterClient, type: :service do
  let(:config) { { provider: "openrouter", api_key: "or-test-key" } }

  def faraday_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def faraday_connection_stub
    @faraday_connection_stub ||= begin
      options = Struct.new(:timeout, :open_timeout).new
      conn = instance_double("Faraday::Connection")
      allow(conn).to receive(:options).and_return(options)
      allow(conn).to receive(:request)
      allow(conn).to receive(:adapter)
      allow(Faraday).to receive(:new).and_yield(conn).and_return(conn)
      conn
    end
  end

  def stub_faraday_post(response)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value); self.path = value; end
    end
    request = request_class.new(headers: {})
    allow(faraday_connection_stub).to receive(:post).and_yield(request).and_return(response)
    request
  end

  describe "#configured?" do
    it "is true when api_key is present" do
      expect(described_class.new(config).configured?).to eq(true)
    end

    it "is false when api_key is missing" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENROUTER_API_KEY").and_return(nil)
      expect(described_class.new({ provider: "openrouter" }).configured?).to eq(false)
    end
  end

  describe "#generate_completion" do
    it "POSTs to https://openrouter.ai/api/v1/chat/completions with HTTP-Referer and X-Title headers" do
      request = stub_faraday_post(faraday_response(
        success: true,
        body: { choices: [{ message: { content: "hello world" } }] }.to_json
      ))

      result = described_class.new(config).generate_completion("hi", model: "openai/gpt-4o-mini")

      expect(result).to eq("hello world")
      expect(request.path).to eq("/chat/completions")
      expect(request.headers["Authorization"]).to eq("Bearer or-test-key")
      expect(request.headers["HTTP-Referer"]).to eq("https://completionkit.com")
      expect(request.headers["X-Title"]).to eq("CompletionKit")
      body = JSON.parse(request.body)
      expect(body["model"]).to eq("openai/gpt-4o-mini")
      expect(body["messages"]).to eq([{ "role" => "user", "content" => "hi" }])
    end

    it "uses default model when none is provided" do
      stub_faraday_post(faraday_response(
        success: true,
        body: { choices: [{ message: { content: "ok" } }] }.to_json
      ))
      result = described_class.new(config).generate_completion("hi")
      expect(result).to eq("ok")
    end

    it "returns an error string when api_key is not configured" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENROUTER_API_KEY").and_return(nil)
      result = described_class.new({ provider: "openrouter" }).generate_completion("hi")
      expect(result).to eq("Error: API key not configured")
    end

    it "returns an error string when the response is not successful" do
      stub_faraday_post(faraday_response(success: false, status: 500, body: "boom"))
      result = described_class.new(config).generate_completion("hi")
      expect(result).to include("Error: 500")
    end

    it "rescues Faraday errors and returns an error string" do
      allow(faraday_connection_stub).to receive(:post).and_raise(Faraday::ConnectionFailed.new("nope"))
      result = described_class.new(config).generate_completion("hi")
      expect(result).to eq("Error: nope")
    end

    it "rescues other StandardErrors and returns an error string" do
      allow(faraday_connection_stub).to receive(:post).and_raise(StandardError, "kaboom")
      result = described_class.new(config).generate_completion("hi")
      expect(result).to eq("Error: kaboom")
    end
  end

  describe "#available_models" do
    it "returns an empty list because models come from discovery" do
      expect(described_class.new(config).available_models).to eq([])
    end
  end

  describe "#configuration_errors" do
    it "lists api_key errors when missing" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENROUTER_API_KEY").and_return(nil)
      errors = described_class.new({ provider: "openrouter" }).configuration_errors
      expect(errors).to include(match(/api key/i))
    end

    it "is empty when api_key is present" do
      expect(described_class.new(config).configuration_errors).to eq([])
    end
  end
end
