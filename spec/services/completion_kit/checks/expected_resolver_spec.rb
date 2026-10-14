require "rails_helper"

RSpec.describe CompletionKit::Checks::ExpectedResolver do
  describe ".call" do
    it "returns the expected_output verbatim when no expected_path is given" do
      response = build(:completion_kit_response, expected_output: "5YFBURHE0KP891234", status: "pending")
      expect(described_class.call(response, {})).to eq("5YFBURHE0KP891234")
    end

    it "digs into a JSON answer key at expected_path" do
      response = build(:completion_kit_response, expected_output: '{"vin":"5YFBURHE0KP891234"}', status: "pending")
      expect(described_class.call(response, { "expected_path" => "vin" })).to eq("5YFBURHE0KP891234")
    end

    it "walks a nested expected_path" do
      response = build(:completion_kit_response, expected_output: '{"car":{"vin":"X1"}}', status: "pending")
      expect(described_class.call(response, { "expected_path" => "car.vin" })).to eq("X1")
    end

    it "returns UNRESOLVED when the row has no expected_output" do
      response = build(:completion_kit_response, expected_output: nil, status: "pending")
      expect(described_class.call(response, {})).to be(described_class::UNRESOLVED)
    end

    it "returns UNRESOLVED when the row's expected_output is blank" do
      response = build(:completion_kit_response, expected_output: "   ", status: "pending")
      expect(described_class.call(response, {})).to be(described_class::UNRESOLVED)
    end

    it "returns UNRESOLVED for an expected_path on a non-JSON answer key, never raising" do
      response = build(:completion_kit_response, expected_output: "plain text", status: "pending")
      expect { described_class.call(response, { "expected_path" => "vin" }) }.not_to raise_error
      expect(described_class.call(response, { "expected_path" => "vin" })).to be(described_class::UNRESOLVED)
    end

    it "returns UNRESOLVED when the expected_path key is missing from the JSON" do
      response = build(:completion_kit_response, expected_output: '{"vin":"X1"}', status: "pending")
      expect(described_class.call(response, { "expected_path" => "make" })).to be(described_class::UNRESOLVED)
    end

    it "reads a JSONPath-style expected_path that starts at the root with $." do
      response = build(:completion_kit_response, expected_output: '{"optionCodes":["A","B"]}', status: "pending")
      expect(described_class.call(response, { "expected_path" => "$.optionCodes.1" })).to eq("B")
    end

    it "keeps the whole answer key as text for a text comparison, even when it parses as JSON" do
      response = build(:completion_kit_response, expected_output: '"quoted"', status: "pending")
      expect(described_class.call(response, {})).to eq('"quoted"')
      expect(described_class.call(response, { "expected_path" => "$" })).to eq('"quoted"')
    end

    it "shares the TargetResolver UNRESOLVED sentinel" do
      expect(described_class::UNRESOLVED).to be(CompletionKit::Checks::TargetResolver::UNRESOLVED)
    end
  end

  describe ".call_value" do
    it "keeps the answer key's own type, so a typed comparison is not defeated by stringifying" do
      response = build(:completion_kit_response, expected_output: '{"code":200}', status: "pending")
      expect(described_class.call_value(response, { "expected_path" => "code" })).to eq(200)
      expect(described_class.call(response, { "expected_path" => "code" })).to eq("200")
    end

    it "returns an expected list as a list" do
      response = build(:completion_kit_response, expected_output: '{"codes":["A","B"]}', status: "pending")
      expect(described_class.call_value(response, { "expected_path" => "codes" })).to eq(%w[A B])
    end

    it "returns the whole answer key when no expected_path is given" do
      response = build(:completion_kit_response, expected_output: "X1", status: "pending")
      expect(described_class.call_value(response, {})).to eq("X1")
    end

    it "parses a whole answer key that is JSON, so a number or a boolean keeps its type" do
      expect(described_class.call_value(build(:completion_kit_response, expected_output: "82000", status: "pending"), {})).to eq(82_000)
      expect(described_class.call_value(build(:completion_kit_response, expected_output: "true", status: "pending"), {})).to be(true)
      expect(described_class.call_value(build(:completion_kit_response, expected_output: '["A","B"]', status: "pending"), {})).to eq(%w[A B])
    end

    it "keeps a whole answer key that is not JSON as the text it is" do
      expect(described_class.call_value(build(:completion_kit_response, expected_output: "82,000", status: "pending"), {})).to eq("82,000")
    end

    it "treats a bare $ expected_path as the whole answer key" do
      response = build(:completion_kit_response, expected_output: "82000", status: "pending")
      expect(described_class.call_value(response, { "expected_path" => "$" })).to eq(82_000)
    end

    it "returns UNRESOLVED when the row has no answer key" do
      response = build(:completion_kit_response, expected_output: nil, status: "pending")
      expect(described_class.call_value(response, {})).to be(described_class::UNRESOLVED)
    end
  end
end
