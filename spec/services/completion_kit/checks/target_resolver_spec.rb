require "rails_helper"

RSpec.describe CompletionKit::Checks::TargetResolver do
  describe ".call" do
    it "resolves the response_text target off the response" do
      response = build(:completion_kit_response, response_text: "hi", status: "pending")
      expect(described_class.call(response, { "target" => "response_text" })).to eq("hi")
    end

    it "resolves the input_data target as the raw JSON string" do
      response = build(:completion_kit_response, input_data: { a: 1 }.to_json, status: "pending")
      expect(described_class.call(response, { "target" => "input_data" })).to eq('{"a":1}')
    end

    it "defaults to response_text when no target is given" do
      response = build(:completion_kit_response, response_text: "fallback", status: "pending")
      expect(described_class.call(response, {})).to eq("fallback")
    end

    it "walks a json_path target into the parsed response_text" do
      response = build(:completion_kit_response, response_text: '{"a":{"b":2}}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "a.b" })).to eq("2")
    end

    it "returns the UNRESOLVED sentinel for a json_path target on non-JSON text, never raising" do
      response = build(:completion_kit_response, response_text: "not json", status: "pending")
      expect { described_class.call(response, { "target" => "json_path", "target_path" => "a" }) }.not_to raise_error
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "a" })).to be(described_class::UNRESOLVED)
    end

    it "returns the UNRESOLVED sentinel for a json_path target whose key is missing" do
      response = build(:completion_kit_response, response_text: '{"a":1}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "a.b" })).to be(described_class::UNRESOLVED)
    end

    it "exposes the allowed target set" do
      expect(described_class::TARGETS).to eq(%w[response_text input_data json_path])
    end
  end
end
