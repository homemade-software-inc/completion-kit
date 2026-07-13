require "rails_helper"
require "faraday"
require "json"

RSpec.describe CompletionKit::ModelDiscoveryService, type: :service do
  let(:config) { { provider: "openai", api_key: "test-key" } }

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

  def stub_faraday_get(response)
    request = Struct.new(:headers).new({})
    allow(faraday_connection_stub).to receive(:get).and_yield(request).and_return(response)
    request
  end

  def stub_faraday_post(response)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value); self.path = value; end
    end
    request = request_class.new(headers: {})
    allow(faraday_connection_stub).to receive(:post).and_yield(request).and_return(response)
    request
  end

  describe "#refresh!" do
    it "discovers new models and creates them as active" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [
          { id: "gpt-4.1-mini", object: "model" },
          { id: "gpt-5.4-mini", object: "model" }
        ] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: Good" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.count).to eq(2)
      model = CompletionKit::Model.find_by(model_id: "gpt-4.1-mini")
      expect(model.status).to eq("active")
      expect(model.provider).to eq("openai")
      expect(model.supports_generation).to eq(true)
      expect(model.discovered_at).to be_present
      expect(model.probed_at).to be_present
    end

    it "does not re-probe models that previously failed with a permanent 4xx error (other than 429)" do
      m = CompletionKit::Model.create!(
        provider: "openai", model_id: "tts-1", status: "failed",
        supports_generation: false,
        generation_error: "400 - {\"error\": {\"message\": \"You can't sample from this model.\"}}",
        probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "tts-1", object: "model" }] }.to_json
      ))

      service = described_class.new(config: config)
      expect(service).not_to receive(:probe_generation)
      expect(service).not_to receive(:probe_judging)
      service.refresh!

      expect(m.reload.generation_error).to start_with("400 -")
      expect(m.reload.probed_at).to be_within(2.seconds).of(1.hour.ago)
    end

    it "re-probes a permanently-4xx-failed model when forced" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-was-broken", status: "failed",
        supports_generation: false,
        generation_error: "400 - {\"error\": {\"message\": \"max_tokens too large\"}}",
        probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-was-broken", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: ok" }] }] }.to_json
      ))

      described_class.new(config: config).refresh!(force: true)

      m = CompletionKit::Model.find_by(model_id: "gpt-was-broken")
      expect(m.supports_generation).to eq(true)
      expect(m.generation_error).to be_nil
      expect(m.status).to eq("active")
    end

    it "leaves confirmed-good models untouched when forced" do
      good = CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-good", status: "active",
        supports_generation: true, supports_judging: true, probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-good", object: "model" }] }.to_json
      ))

      described_class.new(config: config).refresh!(force: true)

      expect(good.reload.probed_at).to be_within(2.seconds).of(1.hour.ago)
    end

    it "does re-probe models that previously failed with a transient 429 rate limit" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-rate-limited", status: "failed",
        supports_generation: false,
        generation_error: "429 - rate limited",
        probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-rate-limited", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: ok" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      m = CompletionKit::Model.find_by(model_id: "gpt-rate-limited")
      expect(m.supports_generation).to eq(true)
      expect(m.status).to eq("active")
    end

    it "does re-probe models that failed with non-HTTP errors like Empty response" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-empty-before", status: "failed",
        supports_generation: false,
        generation_error: "Empty response",
        probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-empty-before", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: ok" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      m = CompletionKit::Model.find_by(model_id: "gpt-empty-before")
      expect(m.supports_generation).to eq(true)
      expect(m.status).to eq("active")
    end

    it "retires models that disappear from the API" do
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-old", status: "active", discovered_at: 1.day.ago)

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-old")
      expect(model.status).to eq("retired")
      expect(model.retired_at).to be_present
    end

    it "re-activates a retired model that reappears in the API" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-comeback", status: "retired",
        supports_generation: true, supports_judging: true, probed_at: 1.day.ago,
        discovered_at: 2.days.ago, retired_at: 1.day.ago
      )

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-comeback", object: "model" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-comeback")
      expect(model.status).to eq("active")
      expect(model.retired_at).to be_nil
    end

    it "does not re-probe existing models" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-4.1-mini", status: "active",
        supports_generation: true, supports_judging: true, probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-4.1-mini", object: "model" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.count).to eq(1)
      expect(CompletionKit::Model.first.probed_at).to be < 1.minute.ago
    end

    it "marks generation as failed when probe returns error" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-broken", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: false,
        status: 404,
        body: '{"error":{"message":"model not found"}}'
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-broken")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to include("404")
      expect(model.status).to eq("failed")
    end

    it "marks generation failed when the model replies but does not follow the text completion instruction" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "image-gen-only", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "I am an image generation model and cannot produce text completions." }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "image-gen-only")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to include("Did not follow text completion instruction")
    end

    it "marks judging as failed when probe response is not parseable" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-nojudge", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nI refuse to score things" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-nojudge")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to be_present
      expect(model.status).to eq("active")
    end

    it "raises DiscoveryError when openai fetch returns non-success response" do
      stub_faraday_get(faraday_response(success: false, status: 401, body: "Unauthorized"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Invalid API key for openai/)
      expect(CompletionKit::Model.where(provider: "openai").count).to eq(0)
    end

    it "raises DiscoveryError when openai responds with 401, preserving existing models" do
      stub_faraday_get(faraday_response(
        success: false,
        status: 401,
        body: { error: { message: "Invalid API key" } }.to_json
      ))

      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-existing", status: "active", discovered_at: 1.day.ago)

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Invalid API key for openai.*Invalid API key/)
      expect(CompletionKit::Model.find_by(model_id: "gpt-existing").status).to eq("active")
    end

    it "raises DiscoveryError with rate-limit label when openai responds with 429" do
      stub_faraday_get(faraday_response(success: false, status: 429, body: "Slow down"))
      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Rate limited by openai/)
    end

    it "raises DiscoveryError with generic label when openai responds with an unmapped status" do
      stub_faraday_get(faraday_response(success: false, status: 418, body: "I'm a teapot"))
      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /openai model list request failed \(418\)/)
    end

    it "raises DiscoveryError without detail when error body is blank" do
      stub_faraday_get(faraday_response(success: false, status: 401, body: ""))
      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |e|
        expect(e.message).to eq("Invalid API key for openai")
      end
    end

    it "raises DiscoveryError using the bare error string when JSON has only error: <string>" do
      stub_faraday_get(faraday_response(success: false, status: 401, body: { error: "key revoked" }.to_json))
      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Invalid API key for openai: key revoked/)
    end

    it "marks generation failed with empty response body" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-empty", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-empty")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to eq("Empty response")
      expect(model.status).to eq("failed")
    end

    it "marks generation failed when openai returns only reasoning chunks (no message item)" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-no-message", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "reasoning", summary: "thinking but never replied" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-no-message")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to eq("Empty response")
    end

    it "skips reasoning-only output items and reads the message item for capability detection" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-reasoning-judge", object: "model" }] }.to_json
      ))
      call_count = 0
      allow(faraday_connection_stub).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        if call_count == 1
          faraday_response(success: true, body: {
            output: [
              { type: "reasoning", summary: "thinking..." },
              { type: "message", content: [{ type: "output_text", text: "PING-OK" }] }
            ]
          }.to_json)
        else
          faraday_response(success: true, body: {
            output: [
              { type: "reasoning", summary: "weighing the score" },
              { type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: clear" }] }
            ]
          }.to_json)
        end
      end

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-reasoning-judge")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
    end

    it "marks generation failed when probe raises StandardError" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-crash", object: "model" }] }.to_json
      ))
      allow(faraday_connection_stub).to receive(:post).and_raise(StandardError, "connection refused")

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-crash")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to eq("connection refused")
      expect(model.status).to eq("failed")
    end

    it "marks judging failed when judge probe returns HTTP error" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-judge-err", object: "model" }] }.to_json
      ))

      call_count = 0
      allow(faraday_connection_stub).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        if call_count == 1
          faraday_response(success: true, body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK" }] }] }.to_json)
        else
          faraday_response(success: false, status: 500, body: "Internal Server Error")
        end
      end

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-judge-err")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to include("500")
    end

    it "retries the openai probe without reasoning effort when the model rejects it" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-5-snobby", object: "model" }] }.to_json
      ))

      call_count = 0
      allow(faraday_connection_stub).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        body = JSON.parse(req.body)
        if body["reasoning"]
          faraday_response(success: false, status: 400, body: %(Unsupported value: 'low' is not supported with the 'gpt-5-snobby' model.))
        else
          faraday_response(success: true, body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK\nScore: 4\nFeedback: ok" }] }] }.to_json)
        end
      end

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-5-snobby")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
      expect(call_count).to be >= 2
    end

    it "marks judging failed when judge probe raises StandardError" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-judge-crash", object: "model" }] }.to_json
      ))

      call_count = 0
      allow(faraday_connection_stub).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        if call_count == 1
          faraday_response(success: true, body: { output: [{ type: "message", content: [{ type: "output_text", text: "PING-OK" }] }] }.to_json)
        else
          raise StandardError, "judge exploded"
        end
      end

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-judge-crash")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to eq("judge exploded")
    end
  end

  describe "#refresh! for anthropic" do
    let(:config) { { provider: "anthropic", api_key: "anthropic-key" } }

    it "discovers anthropic models with display names and probes them" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [
          { id: "claude-3-7-sonnet-latest", display_name: "Claude 3.7 Sonnet" }
        ] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { content: [{ type: "text", text: "PING-OK\nScore: 5\nFeedback: Great" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-3-7-sonnet-latest")
      expect(model.status).to eq("active")
      expect(model.provider).to eq("anthropic")
      expect(model.display_name).to eq("Claude 3.7 Sonnet")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
      expect(model.probed_at).to be_present
    end

    it "raises DiscoveryError when anthropic fetch returns 5xx" do
      stub_faraday_get(faraday_response(
        success: false,
        status: 500,
        body: "Internal Server Error"
      ))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /anthropic returned 500/)
      expect(CompletionKit::Model.where(provider: "anthropic").count).to eq(0)
    end

    it "updates display_name on existing anthropic model" do
      CompletionKit::Model.create!(
        provider: "anthropic", model_id: "claude-3-7-sonnet-latest", status: "active",
        supports_generation: true, supports_judging: true, probed_at: 1.hour.ago,
        discovered_at: 1.day.ago, display_name: nil
      )

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [
          { id: "claude-3-7-sonnet-latest", display_name: "Claude 3.7 Sonnet" }
        ] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-3-7-sonnet-latest")
      expect(model.display_name).to eq("Claude 3.7 Sonnet")
    end

    it "probes anthropic models with a max_tokens within Claude output caps (Haiku 4.5 rejects > 64000)" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5" }] }.to_json
      ))
      probe_request = stub_faraday_post(faraday_response(
        success: true,
        body: { content: [{ type: "text", text: "PING-OK\nScore: 5\nFeedback: ok" }] }.to_json
      ))

      described_class.new(config: config).refresh!

      expect(JSON.parse(probe_request.body)["max_tokens"]).to be <= 64_000
    end

    it "reads the text block past a leading thinking block (thinking-by-default models like claude-fable-5)" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "claude-fable-5", display_name: "Claude Fable 5" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { content: [
          { type: "thinking", thinking: "" },
          { type: "text", text: "PING-OK\nScore: 5\nFeedback: clear" }
        ] }.to_json
      ))

      described_class.new(config: config).refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-fable-5")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
    end

    it "marks anthropic generation failed when the response carries no text block" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "claude-thinky" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { content: [{ type: "thinking", thinking: "hmm" }] }.to_json
      ))

      described_class.new(config: config).refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-thinky")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to eq("Empty response")
    end

    it "marks anthropic model generation as failed on error" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "claude-broken" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: false,
        status: 400,
        body: '{"error":{"message":"bad request"}}'
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-broken")
      expect(model.supports_generation).to eq(false)
      expect(model.status).to eq("failed")
    end
  end

  describe "#refresh! for openrouter" do
    let(:config) { { provider: "openrouter", api_key: "or-test" } }

    let(:openrouter_response_body) do
      {
        data: [
          { id: "openai/gpt-4o-mini", name: "GPT-4o Mini", context_length: 128_000, architecture: { output_modalities: ["text"] } },
          { id: "vendor/no-modalities", name: "No Modalities", context_length: 64_000 },
          { id: "vendor/image-gen", name: "Image Gen", context_length: 32_000, architecture: { output_modalities: ["image"] } },
          { id: "tiny/legacy-2k", name: "Legacy 2k", context_length: 2_048, architecture: { output_modalities: ["text"] } },
          { id: "deprecated/old-model", name: "Old Model", context_length: 32_000, deprecated: true, architecture: { output_modalities: ["text"] } }
        ]
      }.to_json
    end

    it "derives capabilities from metadata: text models judge-capable, image models not, all probed-stamped" do
      stub_faraday_get(faraday_response(success: true, body: openrouter_response_body))

      described_class.new(config: config).refresh!

      models = CompletionKit::Model.where(provider: "openrouter").index_by(&:model_id)
      expect(models.keys).to contain_exactly("openai/gpt-4o-mini", "vendor/no-modalities", "vendor/image-gen")

      text_model = models["openai/gpt-4o-mini"]
      expect(text_model).to have_attributes(supports_generation: true, supports_judging: true, status: "active")
      expect(text_model.probed_at).to be_present

      expect(models["vendor/no-modalities"]).to have_attributes(supports_generation: true, supports_judging: true, status: "active")

      image_model = models["vendor/image-gen"]
      expect(image_model).to have_attributes(supports_generation: false, supports_judging: false, status: "failed")
      expect(image_model.probed_at).to be_present
    end

    it "does not make any live probe calls for openrouter" do
      stub_faraday_get(faraday_response(success: true, body: openrouter_response_body))

      service = described_class.new(config: config)
      expect(service).not_to receive(:probe_generation)
      expect(service).not_to receive(:probe_judging)
      expect(faraday_connection_stub).not_to receive(:post)
      service.refresh!
    end

    it "stores display_name from the openrouter API name field" do
      stub_faraday_get(faraday_response(success: true, body: openrouter_response_body))
      described_class.new(config: config).refresh!
      expect(CompletionKit::Model.find_by(model_id: "openai/gpt-4o-mini").display_name).to eq("GPT-4o Mini")
    end

    it "re-derives supports_generation and supports_judging from metadata on refresh" do
      stale_false = CompletionKit::Model.create!(
        provider: "openrouter", model_id: "openai/gpt-4o-mini", display_name: "old name",
        status: "active", supports_generation: true, supports_judging: false, judging_error: "old probe failure", probed_at: 1.day.ago
      )
      unknown = CompletionKit::Model.create!(
        provider: "openrouter", model_id: "vendor/no-modalities", display_name: "No Modalities",
        status: "active", supports_generation: true, supports_judging: nil
      )
      regressed = CompletionKit::Model.create!(
        provider: "openrouter", model_id: "vendor/image-gen", display_name: "Image Gen",
        status: "active", supports_generation: true, supports_judging: true
      )
      stub_faraday_get(faraday_response(success: true, body: openrouter_response_body))

      described_class.new(config: config).refresh!

      expect(stale_false.reload).to have_attributes(supports_judging: true, supports_generation: true, status: "active", display_name: "GPT-4o Mini", judging_error: nil)
      expect(unknown.reload).to have_attributes(supports_judging: true, supports_generation: true, status: "active")
      expect(regressed.reload).to have_attributes(supports_generation: false, supports_judging: false, status: "failed")
    end

    it "raises DiscoveryError when openrouter fetch returns 401" do
      stub_faraday_get(faraday_response(success: false, status: 401, body: "Unauthorized"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Invalid API key for openrouter/)
      expect(CompletionKit::Model.where(provider: "openrouter").count).to eq(0)
    end
  end

  describe "#refresh! for ollama" do
    let(:config) { { provider: "ollama", api_key: nil, api_endpoint: "http://localhost:11434/v1" } }

    let(:ollama_response_body) do
      {
        data: [
          { id: "llama3.3:70b", object: "model" },
          { id: "qwen2.5:7b", object: "model" },
          { id: "mistral:latest", object: "model" }
        ]
      }.to_json
    end

    let(:ollama_judge_response) do
      faraday_response(success: true, body: { choices: [{ message: { content: "Score: 3\nFeedback: ok" } }] }.to_json)
    end

    it "discovers ollama models, marks supports_generation true and probes judging" do
      stub_faraday_get(faraday_response(success: true, body: ollama_response_body))
      stub_faraday_post(ollama_judge_response)

      service = described_class.new(config: config)
      service.refresh!

      models = CompletionKit::Model.where(provider: "ollama")
      expect(models.pluck(:model_id)).to contain_exactly(
        "llama3.3:70b",
        "qwen2.5:7b",
        "mistral:latest"
      )
      expect(models.where(supports_generation: true).count).to eq(3)
      expect(models.where(supports_judging: true).count).to eq(3)
      expect(models.where("probed_at IS NOT NULL").count).to eq(3)
      expect(models.find_by(model_id: "llama3.3:70b").display_name).to eq("llama3.3:70b")
    end

    it "handles an empty ollama response" do
      stub_faraday_get(faraday_response(success: true, body: { data: [] }.to_json))

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.where(provider: "ollama").count).to eq(0)
    end

    it "skips generation probing for ollama (assumed supported) but probes judging" do
      stub_faraday_get(faraday_response(success: true, body: ollama_response_body))
      stub_faraday_post(ollama_judge_response)

      service = described_class.new(config: config)
      expect(service).not_to receive(:probe_generation)
      expect(service).to receive(:probe_judging).at_least(:once).and_call_original
      service.refresh!
    end

    it "sends ollama judge probes to the configured endpoint at /v1/chat/completions" do
      stub_faraday_get(faraday_response(success: true, body: ollama_response_body))
      probe_request = stub_faraday_post(ollama_judge_response)

      described_class.new(config: { provider: "ollama", api_key: "secret", api_endpoint: "http://localhost:11434/v1" }).refresh!

      expect(probe_request.path).to eq("/v1/chat/completions")
      expect(probe_request.headers["Authorization"]).to eq("Bearer secret")
    end

    it "lists ollama models at /v1/models, stripping a trailing /v1 from the configured endpoint so Ollama doesn't 404" do
      stub_faraday_post(ollama_judge_response)
      conn = faraday_connection_stub
      request = Struct.new(:headers).new({})
      allow(conn).to receive(:get).and_yield(request).and_return(faraday_response(success: true, body: ollama_response_body))

      described_class.new(config: { provider: "ollama", api_key: nil, api_endpoint: "http://localhost:11434/v1" }).refresh!

      expect(conn).to have_received(:get).with("/v1/models")
    end

    it "omits Authorization header on ollama probe when api_key is missing" do
      stub_faraday_get(faraday_response(success: true, body: ollama_response_body))
      probe_request = stub_faraday_post(ollama_judge_response)

      described_class.new(config: { provider: "ollama", api_key: nil, api_endpoint: "http://localhost:11434/v1" }).refresh!

      expect(probe_request.headers).not_to have_key("Authorization")
    end

    it "raises DiscoveryError without leaking the internal slug when api_endpoint is nil" do
      service = described_class.new(config: { provider: "ollama", api_key: nil, api_endpoint: nil })
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to match(/endpoint URL is required/i)
        expect(error.message).not_to match(/ollama/i)
      end
      expect(CompletionKit::Model.where(provider: "ollama").count).to eq(0)
    end

    it "raises DiscoveryError with an actionable, non-leaky message when the endpoint 5xxes" do
      stub_faraday_get(faraday_response(success: false, status: 500, body: "Internal Server Error"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to match(/500/)
        expect(error.message).to match(%r{/v1/models})
        expect(error.message).not_to match(/ollama/i)
      end
      expect(CompletionKit::Model.where(provider: "ollama").count).to eq(0)
    end

    it "explains a 404 at the model-list path and what to check, without leaking the slug" do
      stub_faraday_get(faraday_response(success: false, status: 404, body: { error: { message: "Resource not found" } }.to_json))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to match(%r{/v1/models})
        expect(error.message).to match(/404/)
        expect(error.message).to match(/base URL/i)
        expect(error.message).not_to match(/ollama/i)
      end
    end

    it "points Azure hosts at the Azure AI Foundry provider on a 404" do
      stub_faraday_get(faraday_response(success: false, status: 404, body: "Resource not found"))

      service = described_class.new(config: { provider: "ollama", api_key: "k",
        api_endpoint: "https://my-resource.openai.azure.com" })
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /Azure AI Foundry/)
    end

    it "omits a detail suffix when the endpoint returns no error body" do
      stub_faraday_get(faraday_response(success: false, status: 500, body: ""))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(
        CompletionKit::ModelDiscoveryService::DiscoveryError,
        "The endpoint at localhost did not return an OpenAI-compatible model list at /v1/models (500)."
      )
    end

    it "falls back to the raw endpoint string in the message when the host cannot be parsed" do
      stub_faraday_get(faraday_response(success: false, status: 404, body: ""))

      service = described_class.new(config: { provider: "ollama", api_key: nil, api_endpoint: "not a url" })
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, %r{not a url/v1/models})
    end

    it "reports a rate-limited custom endpoint clearly" do
      stub_faraday_get(faraday_response(success: false, status: 429, body: "Too Many Requests"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(
        CompletionKit::ModelDiscoveryService::DiscoveryError, /rate-limited the model-list request \(429\)/
      )
    end

    it "reports an invalid key on the custom endpoint without leaking the slug" do
      stub_faraday_get(faraday_response(success: false, status: 401, body: "Unauthorized"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to match(/401/)
        expect(error.message).not_to match(/ollama/i)
      end
    end

    it "sends Authorization header when api_key is present" do
      request = stub_faraday_get(faraday_response(success: true, body: ollama_response_body))
      stub_faraday_post(ollama_judge_response)

      service = described_class.new(config: { provider: "ollama", api_key: "secret", api_endpoint: "http://localhost:11434/v1" })
      service.refresh!

      expect(request.headers["Authorization"]).to eq("Bearer secret")
    end
  end

  describe "#refresh! for azure_foundry" do
    let(:config) do
      { provider: "azure_foundry", api_key: "azure-key",
        api_endpoint: "https://my-resource.openai.azure.com", api_version: "2024-10-21" }
    end

    let(:deployments_body) do
      { data: [
        { id: "my-gpt4o", model: "gpt-4o", object: "deployment" },
        { id: "my-mini", model: "gpt-4o-mini", object: "deployment" }
      ] }.to_json
    end

    let(:probe_response) do
      faraday_response(success: true, body: { choices: [{ message: { content: "PING-OK\nScore: 3\nFeedback: ok" } }] }.to_json)
    end

    it "lists deployments at /openai/deployments with the api-version and api-key header" do
      request = stub_faraday_get(faraday_response(success: true, body: deployments_body))
      stub_faraday_post(probe_response)

      described_class.new(config: config).refresh!

      expect(faraday_connection_stub).to have_received(:get).with("/openai/deployments?api-version=2024-10-21")
      expect(request.headers["api-key"]).to eq("azure-key")
    end

    it "creates each deployment as a model and probes generation and judging" do
      stub_faraday_get(faraday_response(success: true, body: deployments_body))
      probe = stub_faraday_post(probe_response)

      described_class.new(config: config).refresh!

      models = CompletionKit::Model.where(provider: "azure_foundry")
      expect(models.pluck(:model_id)).to contain_exactly("my-gpt4o", "my-mini")
      expect(models.where(supports_generation: true).count).to eq(2)
      expect(models.where(supports_judging: true).count).to eq(2)
      expect(models.where("probed_at IS NOT NULL").count).to eq(2)
      expect(probe.path).to match(%r{\A/openai/deployments/.+/chat/completions\?api-version=2024-10-21\z})
      expect(probe.headers["api-key"]).to eq("azure-key")
    end

    it "raises a clean DiscoveryError when the deployments list 404s" do
      stub_faraday_get(faraday_response(success: false, status: 404, body: "Resource not found"))

      service = described_class.new(config: config)
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to match(/deployments/)
        expect(error.message).to match(/api-version/)
      end
      expect(CompletionKit::Model.where(provider: "azure_foundry").count).to eq(0)
    end

    it "raises DiscoveryError when the endpoint is missing" do
      service = described_class.new(config: config.merge(api_endpoint: nil))
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError, /endpoint/i)
    end

    it "uses the v1 API (no api-version) for discovery and probing when the api-version is blank" do
      stub_faraday_get(faraday_response(success: true, body: deployments_body))
      probe = stub_faraday_post(probe_response)

      described_class.new(config: config.merge(api_version: nil)).refresh!

      expect(faraday_connection_stub).to have_received(:get).with("/openai/v1/models")
      models = CompletionKit::Model.where(provider: "azure_foundry")
      expect(models.pluck(:model_id)).to contain_exactly("my-gpt4o", "my-mini")
      expect(probe.path).to eq("/openai/v1/chat/completions")
      expect(probe.body).to match(/"model":"my-(gpt4o|mini)"/)
    end

    it "reports the v1 model-list path (not api-version) when v1 discovery fails" do
      stub_faraday_get(faraday_response(success: false, status: 404, body: "not found"))

      service = described_class.new(config: config.merge(api_version: nil))
      expect { service.refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
        expect(error.message).to include("/openai/v1/models")
        expect(error.message).not_to include("api-version")
      end
    end

    context "with a Foundry project endpoint" do
      let(:project_config) do
        { provider: "azure_foundry", api_key: "azure-key",
          api_endpoint: "https://res.example.test/api/projects/notes", api_version: nil }
      end

      it "lists the project's deployments at /deployments and probes them" do
        request = stub_faraday_get(faraday_response(success: true, body: {
          value: [{ name: "gpt-5.4-nano-notes", type: "ModelDeployment", capabilities: { chat_completion: "true" } }]
        }.to_json))
        probe = stub_faraday_post(probe_response)

        described_class.new(config: project_config).refresh!

        expect(faraday_connection_stub).to have_received(:get).with("https://res.example.test/api/projects/notes/deployments?api-version=v1")
        models = CompletionKit::Model.where(provider: "azure_foundry")
        expect(models.pluck(:model_id)).to contain_exactly("gpt-5.4-nano-notes")
        expect(models.first.supports_generation).to eq(true)
        expect(request.headers["api-key"]).to eq("azure-key")
        expect(probe.path).to eq("/openai/v1/chat/completions")
      end

      it "reports the /deployments path (not api-version) when the project list fails" do
        stub_faraday_get(faraday_response(success: false, status: 404, body: "not found"))

        expect { described_class.new(config: project_config).refresh! }.to raise_error(CompletionKit::ModelDiscoveryService::DiscoveryError) do |error|
          expect(error.message).to include("/deployments")
          expect(error.message).not_to include("api-version")
        end
      end
    end

    it "retries the probe with max_completion_tokens when the model rejects max_tokens" do
      stub_faraday_get(faraday_response(success: true, body: {
        value: [{ name: "gpt-5.4-nano-notes" }]
      }.to_json))

      allow(faraday_connection_stub).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        if JSON.parse(req.body).key?("max_tokens")
          faraday_response(success: false, status: 400, body: "Unsupported parameter: 'max_tokens' is not supported. Use 'max_completion_tokens' instead.")
        else
          faraday_response(success: true, body: { choices: [{ message: { content: "PING-OK\nScore: 4\nFeedback: ok" } }] }.to_json)
        end
      end

      described_class.new(config: config.merge(api_endpoint: "https://res.example.test/api/projects/notes", api_version: nil)).refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-5.4-nano-notes")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
    end
  end

  describe "#refresh! for unknown provider" do
    let(:config) { { provider: "unknown", api_key: "key" } }

    it "raises ArgumentError when send_probe is invoked for an unsupported provider" do
      service = described_class.new(config: config)
      expect { service.send(:send_probe, "any-model", "hi", 10) }.to raise_error(ArgumentError, /Unsupported probe provider/)
    end

    it "returns empty models and retires any existing" do
      CompletionKit::Model.create!(provider: "unknown", model_id: "some-model", status: "active", discovered_at: 1.day.ago)

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.find_by(model_id: "some-model").status).to eq("retired")
    end
  end

  describe "progress callback" do
    let(:service) { described_class.new(config: config) }

    before do
      allow(service).to receive(:fetch_models).and_return([])
    end

    it "accepts an optional progress block" do
      expect { service.refresh! { |current, total| } }.not_to raise_error
    end
  end

  describe "progress callback during probing" do
    let(:service) { described_class.new(config: config) }

    before do
      allow(service).to receive(:fetch_models).and_return([
        { id: "gpt-test-1", display_name: nil },
        { id: "gpt-test-2", display_name: nil }
      ])
      allow(service).to receive(:send_probe).and_return(
        instance_double(Faraday::Response, success?: false, body: "error", status: 400)
      )
    end

    it "yields current count and total after each model probe" do
      progress_updates = []
      service.refresh! { |current, total| progress_updates << [current, total] }
      expect(progress_updates).to eq([[1, 2], [2, 2]])
    end

    it "works without a block" do
      expect { service.refresh! }.not_to raise_error
    end
  end

  describe "duplicate model ids in a discovery response" do
    it "creates each model once instead of crashing on a uniqueness violation" do
      service = described_class.new(config: { provider: "openai", api_key: "k" })
      discovered = [
        { id: "gpt-dup", display_name: "Dup" },
        { id: "gpt-dup", display_name: "Dup" },
        { id: "gpt-unique", display_name: "Unique" }
      ]

      expect { service.send(:reconcile, discovered) }.not_to raise_error
      expect(CompletionKit::Model.where(provider: "openai").pluck(:model_id)).to contain_exactly("gpt-dup", "gpt-unique")
    end
  end
end
