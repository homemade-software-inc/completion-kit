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
  end
end
