require "rails_helper"
require "faraday"
require "json"

RSpec.describe CompletionKit::OllamaClient, type: :service do
  around do |example|
    original = {
      key: CompletionKit.config.ollama_api_key,
      endpoint: CompletionKit.config.ollama_api_endpoint,
      tenant_scope: CompletionKit.config.tenant_scope,
      loopback: CompletionKit.config.allow_loopback_endpoints
    }
    example.run
  ensure
    CompletionKit.config.ollama_api_key = original[:key]
    CompletionKit.config.ollama_api_endpoint = original[:endpoint]
    CompletionKit.config.tenant_scope = original[:tenant_scope]
    CompletionKit.config.allow_loopback_endpoints = original[:loopback]
  end

  before do
    allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"])
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
  end

  def stub_env(values)
    allow(ENV).to receive(:[]).and_call_original
    values.each { |name, value| allow(ENV).to receive(:[]).with(name).and_return(value) }
  end

  def capture_requests
    requests = []
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value)
        self.path = value
      end
    end
    response = instance_double(
      "Faraday::Response",
      success?: true,
      status: 200,
      headers: {},
      body: { choices: [{ text: "Score: 4\nFeedback: ok" }], data: [{ id: "llama3.3" }] }.to_json
    )
    connection = double("Faraday::Connection")
    allow(connection).to receive(:request)
    allow(connection).to receive(:adapter)
    allow(connection).to receive(:options).and_return(Struct.new(:timeout, :open_timeout).new)
    %i[post get].each do |verb|
      allow(connection).to receive(verb) do |&block|
        request = request_class.new(headers: {})
        block.call(request)
        requests << request
        response
      end
    end
    allow(Faraday).to receive(:new).and_yield(connection).and_return(connection)
    requests
  end

  def authorization_sent_by(client)
    requests = capture_requests
    expect(client.generate_completion("prompt", model: "llama3.3")).to eq("Score: 4\nFeedback: ok")
    expect(client.available_models).to eq([{ id: "llama3.3", name: "llama3.3" }])
    requests.map { |request| request.headers["Authorization"] }.uniq
  end

  describe ".configured_endpoint" do
    it "prefers the configured endpoint, then the environment, then the built-in default" do
      stub_env("OLLAMA_API_ENDPOINT" => "https://env-ollama.example.test/v1")
      CompletionKit.config.ollama_api_endpoint = "https://configured-ollama.example.test/v1"
      expect(described_class.configured_endpoint).to eq("https://configured-ollama.example.test/v1")

      CompletionKit.config.ollama_api_endpoint = nil
      expect(described_class.configured_endpoint).to eq("https://env-ollama.example.test/v1")

      stub_env("OLLAMA_API_ENDPOINT" => nil)
      expect(described_class.configured_endpoint).to eq("http://localhost:11434/v1")

      CompletionKit.config.allow_loopback_endpoints = false
      expect(described_class.configured_endpoint).to be_nil
    end
  end

  context "when the credential has no key of its own" do
    it "sends the configured key to the configured endpoint, however the URL is written" do
      CompletionKit.config.ollama_api_key = "configured-key"
      CompletionKit.config.ollama_api_endpoint = "https://ollama.example.test/v1"

      client = described_class.new(api_endpoint: "HTTPS://Ollama.Example.test:443/v1/")
      expect(authorization_sent_by(client)).to eq(["Bearer configured-key"])
    end

    it "sends the environment key to the environment endpoint" do
      stub_env("OLLAMA_API_KEY" => "env-key", "OLLAMA_API_ENDPOINT" => "https://ollama.example.test/v1")

      expect(authorization_sent_by(described_class.new)).to eq(["Bearer env-key"])
      expect(authorization_sent_by(described_class.new(api_endpoint: "https://ollama.example.test/v1"))).to eq(["Bearer env-key"])
    end

    it "sends the fallback key to the built-in default endpoint when no endpoint is configured" do
      stub_env("OLLAMA_API_KEY" => "env-key")

      expect(authorization_sent_by(described_class.new)).to eq(["Bearer env-key"])
      expect(authorization_sent_by(described_class.new(api_endpoint: "http://localhost:11434/v1"))).to eq(["Bearer env-key"])
    end

    it "sends no fallback key to an endpoint the credential sets for itself" do
      stub_env("OLLAMA_API_KEY" => "env-key", "OLLAMA_API_ENDPOINT" => "https://ollama.example.test/v1")
      CompletionKit.config.ollama_api_key = "configured-key"

      [
        "https://attacker.example.test/v1",
        "http://ollama.example.test/v1",
        "https://ollama.example.test:8443/v1",
        "https://ollama.example.test/other/v1"
      ].each do |endpoint|
        expect(authorization_sent_by(described_class.new(api_endpoint: endpoint))).to eq([nil])
      end
    end

    it "sends no fallback key to the built-in default once an endpoint is configured elsewhere" do
      stub_env("OLLAMA_API_KEY" => "env-key")
      CompletionKit.config.ollama_api_endpoint = "https://ollama.example.test/v1"

      expect(authorization_sent_by(described_class.new(api_endpoint: "http://localhost:11434/v1"))).to eq([nil])
    end

    it "sends no fallback key when loopback endpoints are off and no endpoint is configured" do
      stub_env("OLLAMA_API_KEY" => "env-key")
      CompletionKit.config.allow_loopback_endpoints = false

      expect(described_class.fallback_api_key("http://localhost:11434/v1")).to be_nil
      expect(authorization_sent_by(described_class.new(api_endpoint: "https://ollama.example.test/v1"))).to eq([nil])
    end

    it "keeps the environment key, never the configured one, for tenants" do
      stub_env("OLLAMA_API_KEY" => "env-key", "OLLAMA_API_ENDPOINT" => "https://ollama.example.test/v1")
      CompletionKit.config.ollama_api_key = "deployment-key"
      CompletionKit.config.tenant_scope = -> { all }

      expect(authorization_sent_by(described_class.new(api_endpoint: "https://ollama.example.test/v1"))).to eq(["Bearer env-key"])
      expect(authorization_sent_by(described_class.new(api_endpoint: "https://attacker.example.test/v1"))).to eq([nil])
    end
  end

  it "always sends a key stored on the credential, wherever it points" do
    stub_env("OLLAMA_API_KEY" => "env-key", "OLLAMA_API_ENDPOINT" => "https://ollama.example.test/v1")
    CompletionKit.config.ollama_api_key = "configured-key"

    stored = described_class.new(api_key: "stored-key", api_endpoint: "https://elsewhere.example.test/v1")
    expect(authorization_sent_by(stored)).to eq(["Bearer stored-key"])

    CompletionKit.config.tenant_scope = -> { all }
    expect(authorization_sent_by(stored)).to eq(["Bearer stored-key"])
  end

  context "through a provider credential" do
    before do
      CompletionKit.config.ollama_api_key = "configured-key"
      CompletionKit.config.ollama_api_endpoint = "https://ollama.example.test/v1"
      CompletionKit::Model.create!(provider: "ollama", model_id: "llama3.3", status: "active",
        supports_generation: true, supports_judging: true)
    end

    def requests_for_generation_judging_and_listing(credential)
      requests = capture_requests
      CompletionKit::LlmClient.for_model("llama3.3", CompletionKit::ApiConfig.for_model("llama3.3"))
        .generate_completion("prompt", model: "llama3.3")
      judge = CompletionKit::JudgeService.new(judge_model: "llama3.3")
      expect(judge.evaluate("output")).to eq(score: 4.0, feedback: "ok")
      credential.available_models
      expect(requests.length).to eq(3)
      requests.map { |request| request.headers["Authorization"] }.uniq
    end

    it "sends the configured key to a keyless credential on the configured endpoint" do
      credential = create(:completion_kit_provider_credential, provider: "ollama", api_key: nil,
        api_endpoint: "https://ollama.example.test/v1/")

      expect(requests_for_generation_judging_and_listing(credential)).to eq(["Bearer configured-key"])
    end

    it "sends no key when a keyless credential points somewhere else" do
      credential = create(:completion_kit_provider_credential, provider: "ollama", api_key: nil,
        api_endpoint: "https://attacker.example.test/v1")

      expect(requests_for_generation_judging_and_listing(credential)).to eq([nil])
    end

    it "sends the stored key when the credential has one" do
      credential = create(:completion_kit_provider_credential, provider: "ollama", api_key: "stored-key",
        api_endpoint: "https://elsewhere.example.test/v1")

      expect(requests_for_generation_judging_and_listing(credential)).to eq(["Bearer stored-key"])
    end
  end
end
