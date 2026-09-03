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

    it "walks an array index in a json_path, which the form has always advertised" do
      response = build(:completion_kit_response, response_text: '{"items":[{"name":"a"},{"name":"b"}]}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "items.1.name" })).to eq("b")
    end

    it "returns UNRESOLVED for an array index past the end" do
      response = build(:completion_kit_response, response_text: '{"items":[1]}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "items.5" })).to be(described_class::UNRESOLVED)
    end

    it "returns UNRESOLVED for a non-numeric segment against an array" do
      response = build(:completion_kit_response, response_text: '{"items":[1]}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "items.name" })).to be(described_class::UNRESOLVED)
    end

    it "returns UNRESOLVED when the path runs past a scalar" do
      response = build(:completion_kit_response, response_text: '{"a":1}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "a.b.c" })).to be(described_class::UNRESOLVED)
    end

    it "strips a target_path that was saved with stray whitespace" do
      response = build(:completion_kit_response, response_text: '{"a":1}', status: "pending")
      expect(described_class.call(response, { "target" => "json_path", "target_path" => " a " })).to eq("1")
    end

    it "exposes the allowed target set" do
      expect(described_class::TARGETS).to eq(%w[response_text input_data json_path])
    end
  end

  describe ".call_value" do
    it "returns a list from the response JSON without stringifying it" do
      response = build(:completion_kit_response, response_text: '{"codes":["A","B"]}', status: "pending")
      expect(described_class.call_value(response, { "target" => "json_path", "target_path" => "codes" })).to eq(%w[A B])
    end

    it "keeps a number a number, so a numeric check never parses it back" do
      response = build(:completion_kit_response, response_text: '{"n":5}', status: "pending")
      expect(described_class.call_value(response, { "target" => "json_path", "target_path" => "n" })).to eq(5)
    end

    it "distinguishes a JSON null from the empty string that .call would give" do
      response = build(:completion_kit_response, response_text: '{"n":null}', status: "pending")
      expect(described_class.call_value(response, { "target" => "json_path", "target_path" => "n" })).to be_nil
      expect(described_class.call(response, { "target" => "json_path", "target_path" => "n" })).to eq("")
    end

    it "falls back to the raw response text and input data like .call does" do
      response = build(:completion_kit_response, response_text: "hi", input_data: '{"a":1}', status: "pending")
      expect(described_class.call_value(response, {})).to eq("hi")
      expect(described_class.call_value(response, { "target" => "input_data" })).to eq('{"a":1}')
    end
  end
end
