require "rails_helper"

RSpec.describe CompletionKit::Checks::Registry do
  def call(kind, target, config = {})
    described_class.fetch(kind).call(target, config)
  end

  describe ".kinds" do
    it "exposes the exact v1 catalog of eight kinds" do
      expect(described_class.kinds).to match_array(
        %w[contains not_contains equals regex valid_json json_path_equals length_bounds no_refusal]
      )
    end

    it "freezes the catalog" do
      expect(described_class.kinds).to be_frozen
    end
  end

  describe ".required_keys" do
    it "lists per-kind required config keys for the model validator and form" do
      expect(described_class.required_keys.fetch("contains")).to eq(%w[value])
      expect(described_class.required_keys.fetch("regex")).to eq(%w[pattern])
      expect(described_class.required_keys.fetch("json_path_equals")).to eq(%w[json_path expected])
      expect(described_class.required_keys.fetch("valid_json")).to eq([])
      expect(described_class.required_keys.fetch("length_bounds")).to eq([])
    end
  end

  describe ".fetch" do
    it "returns the callable for a known kind" do
      expect(described_class.fetch("valid_json")).to respond_to(:call)
    end

    it "raises KeyError for an unknown kind (the only genuine exception that propagates)" do
      expect { described_class.fetch("nope") }.to raise_error(KeyError)
    end

    it "evaluates with no database or network" do
      expect(call("contains", "ab", { "value" => "a" })).to have_attributes(passed: true)
    end
  end

  describe "contains" do
    it "passes when the substring is present and fails when absent" do
      expect(call("contains", "hello world", { "value" => "world" }).passed).to be(true)
      expect(call("contains", "hello", { "value" => "world" }).passed).to be(false)
    end

    it "defaults to case-insensitive" do
      expect(call("contains", "HELLO", { "value" => "hello" }).passed).to be(true)
    end

    it "honors case_sensitive: true" do
      expect(call("contains", "HELLO", { "value" => "hello", "case_sensitive" => true }).passed).to be(false)
    end

    it "fails a nil target without raising" do
      expect { call("contains", nil, { "value" => "x" }) }.not_to raise_error
      expect(call("contains", nil, { "value" => "x" }).passed).to be(false)
    end
  end

  describe "not_contains" do
    it "is the explicit inverse with pass = good" do
      expect(call("not_contains", "clean output", { "value" => "error" }).passed).to be(true)
      expect(call("not_contains", "an error here", { "value" => "error" }).passed).to be(false)
    end

    it "passes a nil target (nothing to contain)" do
      expect(call("not_contains", nil, { "value" => "error" }).passed).to be(true)
    end

    it "honors case_sensitive: true" do
      expect(call("not_contains", "an ERROR here", { "value" => "error", "case_sensitive" => true }).passed).to be(true)
    end
  end

  describe "equals" do
    it "compares the whole target" do
      expect(call("equals", "ok", { "value" => "ok" }).passed).to be(true)
      expect(call("equals", "ok!", { "value" => "ok" }).passed).to be(false)
    end

    it "honors trim" do
      expect(call("equals", "  ok  ", { "value" => "ok", "trim" => true }).passed).to be(true)
      expect(call("equals", "  ok  ", { "value" => "ok" }).passed).to be(false)
    end

    it "honors case_sensitive: true" do
      expect(call("equals", "OK", { "value" => "ok" }).passed).to be(true)
      expect(call("equals", "OK", { "value" => "ok", "case_sensitive" => true }).passed).to be(false)
    end
  end

  describe "regex" do
    it "is case-sensitive by default and honors case_sensitive: false" do
      expect(call("regex", "hello", { "pattern" => "ell" }).passed).to be(true)
      expect(call("regex", "HELLO", { "pattern" => "hello" }).passed).to be(false)
      expect(call("regex", "HELLO", { "pattern" => "hello", "case_sensitive" => false }).passed).to be(true)
    end

    it "lets multiline make dot span a newline" do
      expect(call("regex", "A\nB", { "pattern" => "A.B" }).passed).to be(false)
      expect(call("regex", "A\nB", { "pattern" => "A.B", "multiline" => true }).passed).to be(true)
    end

    it "fails an uncompilable pattern rather than raising" do
      expect { call("regex", "x", { "pattern" => "(" }) }.not_to raise_error
      expect(call("regex", "x", { "pattern" => "(" }).passed).to be(false)
    end
  end

  describe "valid_json" do
    it "passes on parseable JSON and fails (never raises) on garbage" do
      expect(call("valid_json", '{"a":1}', {}).passed).to be(true)
      expect { call("valid_json", "{not json", {}) }.not_to raise_error
      expect(call("valid_json", "{not json", {}).passed).to be(false)
    end
  end

  describe "json_path_equals" do
    it "reads a nested value and compares to expected" do
      expect(call("json_path_equals", '{"a":{"b":"x"}}', { "json_path" => "a.b", "expected" => "x" }).passed).to be(true)
    end

    it "fails a missing key without raising" do
      expect { call("json_path_equals", '{"a":1}', { "json_path" => "a.b", "expected" => "x" }) }.not_to raise_error
      expect(call("json_path_equals", '{"a":1}', { "json_path" => "a.b", "expected" => "x" }).passed).to be(false)
    end

    it "compares with strict types (numeric value never equals a string expected)" do
      expect(call("json_path_equals", '{"n":5}', { "json_path" => "n", "expected" => "5" }).passed).to be(false)
      expect(call("json_path_equals", '{"n":5}', { "json_path" => "n", "expected" => 5 }).passed).to be(true)
    end

    it "fails a non-JSON target without raising" do
      expect(call("json_path_equals", "plain text", { "json_path" => "a", "expected" => "x" }).passed).to be(false)
    end
  end

  describe "length_bounds" do
    it "honors a min-only bound" do
      expect(call("length_bounds", "abc", { "min" => 3 }).passed).to be(true)
      expect(call("length_bounds", "ab", { "min" => 3 }).passed).to be(false)
    end

    it "honors a max-only bound" do
      expect(call("length_bounds", "abc", { "max" => 3 }).passed).to be(true)
      expect(call("length_bounds", "abcd", { "max" => 3 }).passed).to be(false)
    end

    it "honors both bounds inclusively" do
      expect(call("length_bounds", "ab", { "min" => 1, "max" => 3 }).passed).to be(true)
      expect(call("length_bounds", "abcd", { "min" => 1, "max" => 3 }).passed).to be(false)
    end

    it "tolerates string bounds without raising (errored check must fail, not crash)" do
      expect { call("length_bounds", "abc", { "min" => "2", "max" => "9" }) }.not_to raise_error
      expect(call("length_bounds", "a", { "min" => "2" }).passed).to be(false)
      expect(call("length_bounds", "abc", { "min" => "2" }).passed).to be(true)
    end
  end

  describe "no_refusal" do
    it "passes a normal answer and fails a refusal" do
      expect(call("no_refusal", "Here is the data you asked for.", {}).passed).to be(true)
      expect(call("no_refusal", "I'm sorry, I can't help with that.", {}).passed).to be(false)
    end

    it "detects each refusal phrasing in the catalog" do
      refusals = [
        "I'm sorry, but that is off limits.",
        "I can't help with that request.",
        "I cannot assist with this.",
        "I'm unable to do that.",
        "I won't be able to help here.",
        "As an AI, I do not have opinions."
      ]
      refusals.each do |phrase|
        expect(call("no_refusal", phrase, {}).passed).to be(false), "expected a refusal for: #{phrase}"
      end
    end
  end
end
