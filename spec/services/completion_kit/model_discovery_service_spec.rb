require "rails_helper"
require "faraday"
require "json"

RSpec.describe CompletionKit::ModelDiscoveryService, type: :service do
  let(:config) { { provider: "openai", api_key: "test-key" } }

  def faraday_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def stub_faraday_get(response)
    request = Struct.new(:headers).new({})
    allow(Faraday).to receive(:get).and_yield(request).and_return(response)
    request
  end

  def stub_faraday_post(response)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value); self.path = value; end
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
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "Score: 4\nFeedback: Good" }] }] }.to_json
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

    it "marks judging as failed when probe response is not parseable" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-nojudge", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "I refuse to score things" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-nojudge")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to be_present
      expect(model.status).to eq("active")
    end

    it "returns empty list when fetch raises an error" do
      allow(Faraday).to receive(:get).and_raise(StandardError, "network down")

      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-existing", status: "active", discovered_at: 1.day.ago)

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.find_by(model_id: "gpt-existing").status).to eq("retired")
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

    it "marks generation failed when probe raises StandardError" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-crash", object: "model" }] }.to_json
      ))
      allow(Faraday).to receive(:new).and_raise(StandardError, "connection refused")

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
      builder = instance_double("Faraday::RackBuilder")
      allow(builder).to receive(:request)
      allow(builder).to receive(:adapter)
      connection = instance_double("Faraday::Connection")
      allow(connection).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        if call_count == 1
          faraday_response(success: true, body: { output: [{ type: "message", content: [{ type: "output_text", text: "Hello!" }] }] }.to_json)
        else
          faraday_response(success: false, status: 500, body: "Internal Server Error")
        end
      end
      allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-judge-err")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to include("500")
    end

    it "marks judging failed when judge probe raises StandardError" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-judge-crash", object: "model" }] }.to_json
      ))

      call_count = 0
      builder = instance_double("Faraday::RackBuilder")
      allow(builder).to receive(:request)
      allow(builder).to receive(:adapter)
      connection = instance_double("Faraday::Connection")
      allow(connection).to receive(:post) do |&block|
        req = Struct.new(:headers, :body, :path, keyword_init: true) do
          def url(value); self.path = value; end
        end.new(headers: {})
        block.call(req) if block
        call_count += 1
        if call_count == 1
          faraday_response(success: true, body: { output: [{ type: "message", content: [{ type: "output_text", text: "Hello!" }] }] }.to_json)
        else
          raise StandardError, "judge exploded"
        end
      end
      allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)

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
        body: { content: [{ type: "text", text: "Score: 5\nFeedback: Great" }] }.to_json
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

    it "returns empty list when anthropic fetch fails" do
      stub_faraday_get(faraday_response(
        success: false,
        status: 500,
        body: "Internal Server Error"
      ))

      service = described_class.new(config: config)
      service.refresh!

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

  describe "#refresh! for unknown provider" do
    let(:config) { { provider: "unknown", api_key: "key" } }

    it "returns empty models and retires any existing" do
      CompletionKit::Model.create!(provider: "unknown", model_id: "some-model", status: "active", discovered_at: 1.day.ago)

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.find_by(model_id: "some-model").status).to eq("retired")
    end
  end
end
