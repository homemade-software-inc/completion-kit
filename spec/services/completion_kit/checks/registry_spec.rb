require "rails_helper"

RSpec.describe CompletionKit::Checks::Registry do
  def call(kind, target, config = {})
    described_class.fetch(kind).call(target, config)
  end

  describe ".kinds" do
    it "exposes the catalog of check kinds" do
      expect(described_class.kinds).to match_array(
        %w[contains not_contains equals regex valid_json json_path_equals length_bounds
           set_overlap numeric_bounds numeric_equals]
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
      expect(described_class.required_keys.fetch("set_overlap")).to eq(%w[value])
      expect(described_class.required_keys.fetch("numeric_bounds")).to eq([])
      expect(described_class.required_keys.fetch("numeric_equals")).to eq(%w[value])
    end
  end

  describe ".compares_value?" do
    it "is true only for the kinds whose operand can come from a constant or the row's expected value" do
      expect(described_class.compares_value?("contains")).to be(true)
      expect(described_class.compares_value?("not_contains")).to be(true)
      expect(described_class.compares_value?("equals")).to be(true)
      expect(described_class.compares_value?("json_path_equals")).to be(true)
      expect(described_class.compares_value?("set_overlap")).to be(true)
      expect(described_class.compares_value?("numeric_equals")).to be(true)
      expect(described_class.compares_value?("valid_json")).to be(false)
      expect(described_class.compares_value?("numeric_bounds")).to be(false)
    end
  end

  describe ".expected_key" do
    it "names the config key that the row's expected value fills in" do
      expect(described_class.expected_key("equals")).to eq("value")
      expect(described_class.expected_key("set_overlap")).to eq("value")
      expect(described_class.expected_key("numeric_equals")).to eq("value")
    end

    it "is expected rather than value for json_path_equals, which already had a constant operand" do
      expect(described_class.expected_key("json_path_equals")).to eq("expected")
    end

    it "is nil for a kind with no operand" do
      expect(described_class.expected_key("valid_json")).to be_nil
    end
  end

  describe ".comparable_kinds" do
    it "lists every kind that accepts compare_to expected, for the validation message" do
      expect(described_class.comparable_kinds).to match_array(
        %w[contains not_contains equals json_path_equals set_overlap numeric_equals]
      )
    end
  end

  describe ".config_keys" do
    it "lists the keys each kind actually reads" do
      expect(described_class.config_keys("regex")).to eq(%w[pattern case_sensitive multiline])
      expect(described_class.config_keys("set_overlap")).to eq(%w[value measure min case_sensitive])
      expect(described_class.config_keys("numeric_equals")).to eq(%w[value tolerance tolerance_mode])
      expect(described_class.config_keys("valid_json")).to eq([])
    end

    it "returns nothing for an unknown kind rather than raising" do
      expect(described_class.config_keys("nope")).to eq([])
    end
  end

  describe ".raw_target? and .raw_expected?" do
    it "marks the kinds that compare parsed JSON rather than strings" do
      expect(described_class.raw_target?("set_overlap")).to be(true)
      expect(described_class.raw_target?("numeric_bounds")).to be(true)
      expect(described_class.raw_target?("numeric_equals")).to be(true)
      expect(described_class.raw_target?("equals")).to be(false)
    end

    it "reads the expected value raw wherever the operand is typed, including json_path_equals" do
      expect(described_class.raw_expected?("json_path_equals")).to be(true)
      expect(described_class.raw_expected?("set_overlap")).to be(true)
      expect(described_class.raw_expected?("numeric_equals")).to be(true)
      expect(described_class.raw_expected?("contains")).to be(false)
    end
  end

  describe ".bounded?" do
    it "marks the kinds validated for a min/max pair" do
      expect(described_class.bounded?("length_bounds")).to be(true)
      expect(described_class.bounded?("numeric_bounds")).to be(true)
      expect(described_class.bounded?("set_overlap")).to be(false)
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

    it "honors trim, which the form has always offered here" do
      expect(call("contains", "hello world", { "value" => " world " }).passed).to be(false)
      expect(call("contains", "hello world", { "value" => " world ", "trim" => true }).passed).to be(true)
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

    it "honors trim" do
      expect(call("not_contains", "error here", { "value" => " error " }).passed).to be(true)
      expect(call("not_contains", "error here", { "value" => " error ", "trim" => true }).passed).to be(false)
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
    it "defaults to case-insensitive, matching every other kind that reads case_sensitive" do
      expect(call("regex", "hello", { "pattern" => "ell" }).passed).to be(true)
      expect(call("regex", "HELLO", { "pattern" => "hello" }).passed).to be(true)
      expect(call("regex", "HELLO", { "pattern" => "hello", "case_sensitive" => false }).passed).to be(true)
    end

    it "honors case_sensitive: true" do
      expect(call("regex", "HELLO", { "pattern" => "hello", "case_sensitive" => true }).passed).to be(false)
    end

    it "honors a case_sensitive that arrived from JSON as a string, which the API never coerces" do
      expect(call("regex", "HELLO", { "pattern" => "hello", "case_sensitive" => "true" }).passed).to be(false)
      expect(call("regex", "HELLO", { "pattern" => "hello", "case_sensitive" => "false" }).passed).to be(true)
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

    it "treats a blank bound as absent rather than as zero" do
      expect(call("length_bounds", "abc", { "min" => "", "max" => "" }).detail).to eq("length 3 within bounds")
      expect(call("length_bounds", "", { "min" => "", "max" => "2" }).passed).to be(true)
    end

    it "reports an integer bound without a decimal point" do
      expect(call("length_bounds", "a", { "min" => 3 }).detail).to eq("length 1 below min 3")
      expect(call("length_bounds", "abcd", { "max" => 3 }).detail).to eq("length 4 above max 3")
    end
  end

  describe "set_overlap" do
    def overlap(target, config = {})
      call("set_overlap", target, { "value" => %w[a b c d] }.merge(config))
    end

    it "scores recall as the share of the expected set that was returned" do
      result = overlap(%w[a b])
      expect(result.score).to eq(0.5)
      expect(result.detail).to eq("recall 0.5 (2 of 4 expected, 2 returned)")
    end

    it "separates a partial answer from a total miss, which pass/fail cannot" do
      expect(overlap(%w[a b c]).score).to eq(0.75)
      expect(overlap([]).score).to eq(0.0)
    end

    it "scores precision as the share of what was returned that was expected" do
      expect(overlap(%w[a b x y], { "measure" => "precision" }).score).to eq(0.5)
    end

    it "scores jaccard over the union" do
      expect(overlap(%w[a b x], { "measure" => "jaccard" }).score).to eq(0.4)
    end

    it "scores f1 as the harmonic mean of precision and recall" do
      expect(overlap(%w[a b x y], { "measure" => "f1" }).score).to eq(0.5)
    end

    it "scores f1 as zero when nothing overlaps, rather than dividing by zero" do
      expect(overlap(%w[x y], { "measure" => "f1" }).score).to eq(0.0)
    end

    it "falls back to recall for an unrecognised measure" do
      expect(overlap(%w[a b], { "measure" => "nonsense" }).detail).to start_with("recall")
    end

    it "treats an empty expected set as vacuously satisfied only when nothing was returned either" do
      CompletionKit::Checks::SetOverlap::MEASURES.each do |measure|
        expect(call("set_overlap", [], { "value" => [], "measure" => measure }).score).to eq(1.0)
      end
    end

    it "never scores an empty answer as perfect, whichever measure is chosen" do
      CompletionKit::Checks::SetOverlap::MEASURES.each do |measure|
        result = overlap([], { "measure" => measure })
        expect(result.score).to eq(0.0), "#{measure} scored #{result.score} for an empty answer"
        expect(result.passed).to be(false)
      end
    end

    it "scores every measure the same way when nothing was expected but something came back" do
      CompletionKit::Checks::SetOverlap::MEASURES.each do |measure|
        expect(call("set_overlap", %w[x y z], { "value" => [], "measure" => measure }).score).to eq(0.0)
      end
    end

    it "requires an exact match by default and honors a min threshold" do
      expect(overlap(%w[a b c]).passed).to be(false)
      expect(overlap(%w[a b c], { "min" => 0.7 }).passed).to be(true)
      expect(overlap(%w[a b c d]).passed).to be(true)
    end

    it "is case-insensitive by default and honors case_sensitive" do
      expect(overlap(%w[A B C D]).score).to eq(1.0)
      expect(overlap(%w[A B C D], { "case_sensitive" => true }).score).to eq(0.0)
    end

    it "honors a case_sensitive that arrived from JSON as a string" do
      expect(overlap(%w[A B C D], { "case_sensitive" => "true" }).score).to eq(0.0)
      expect(overlap(%w[A B C D], { "case_sensitive" => "false" }).score).to eq(1.0)
    end

    it "reads a JSON array out of a string target" do
      expect(overlap('["a","b"]').score).to eq(0.5)
    end

    it "reads a comma-separated list out of a string target" do
      expect(overlap("a, b, c").score).to eq(0.75)
    end

    it "ignores blank members on both sides" do
      expect(overlap("a, , b").score).to eq(0.5)
    end

    it "counts a repeated member once" do
      expect(overlap(%w[a a a]).score).to eq(0.25)
    end

    it "treats a target that is not a list as empty rather than raising" do
      expect(overlap(nil).score).to eq(0.0)
      expect(overlap({ "a" => 1 }).score).to eq(0.0)
      expect(overlap("").score).to eq(0.0)
      expect(overlap('{"a":1}').score).to eq(0.0)
    end

    it "reports a JSON object as nothing returned rather than splitting its own source text" do
      expect(overlap('{"codes":["a","b"]}').detail).to eq("recall 0.0 (0 of 4 expected, 0 returned)")
    end

    it "reads a quoted list without carrying the quote characters into the members" do
      expect(overlap('"a", "b"').score).to eq(0.5)
      expect(overlap('"a, b"').score).to eq(0.5)
    end

    it "reads the newline and bulleted lists a model writes by default" do
      expect(overlap("a\nb").score).to eq(0.5)
      expect(overlap("- a\n- b\n- c").score).to eq(0.75)
      expect(overlap("a;b").score).to eq(0.5)
    end

    it "keeps a single unquoted number as one member" do
      expect(call("set_overlap", "123", { "value" => %w[123] }).score).to eq(1.0)
    end
  end

  describe "numeric_bounds" do
    it "bounds an extracted number below and above" do
      expect(call("numeric_bounds", "0.91", { "min" => 0.8 }).passed).to be(true)
      expect(call("numeric_bounds", "0.42", { "min" => 0.8 }).detail).to eq("0.42 is below min 0.8")
      expect(call("numeric_bounds", "2026", { "max" => 2025 }).detail).to eq("2026 is above max 2025")
    end

    it "passes a value inside both bounds" do
      expect(call("numeric_bounds", 1999, { "min" => 1900, "max" => 2030 }).detail).to eq("1999 is within bounds")
    end

    it "reads a formatted figure rather than failing on its punctuation" do
      expect(call("numeric_bounds", "82,000", { "min" => 80_000 }).passed).to be(true)
    end

    it "fails a target that is not a number instead of coercing it to zero" do
      result = call("numeric_bounds", "unknown", { "min" => 0.8 })
      expect(result.passed).to be(false)
      expect(result.detail).to eq("\"unknown\" is not a number")
    end

    it "carries no fractional score, since it is a yes or no" do
      expect(call("numeric_bounds", "1", { "min" => 0 }).score).to be_nil
    end
  end

  describe "numeric_equals" do
    it "compares two numbers exactly when no tolerance is given" do
      expect(call("numeric_equals", "82000", { "value" => "82000" }).passed).to be(true)
      expect(call("numeric_equals", "82001", { "value" => "82000" }).passed).to be(false)
    end

    it "ignores formatting differences that equals would report as wrong" do
      expect(call("numeric_equals", "82,000", { "value" => "82000" }).passed).to be(true)
      expect(call("numeric_equals", "$24,995", { "value" => 24_995 }).passed).to be(true)
    end

    it "accepts a near-enough figure within an absolute tolerance" do
      result = call("numeric_equals", "2019", { "value" => 2020, "tolerance" => 1 })
      expect(result.passed).to be(true)
      expect(result.detail).to eq("2019 vs 2020, within 1")
    end

    it "reports how far out a value is when it misses the tolerance" do
      result = call("numeric_equals", "1980", { "value" => 2020, "tolerance" => 1 })
      expect(result.detail).to eq("1980 vs 2020, off by 40 (allowed 1)")
    end

    it "scales the tolerance to the expected value in relative mode" do
      config = { "value" => 24_995, "tolerance" => 0.02, "tolerance_mode" => "relative" }
      expect(call("numeric_equals", "25400", config).passed).to be(true)
      expect(call("numeric_equals", "26000", config).passed).to be(false)
    end

    it "scales a relative tolerance off the magnitude of a negative expected value" do
      config = { "value" => -100, "tolerance" => 0.1, "tolerance_mode" => "relative" }
      expect(call("numeric_equals", "-105", config).passed).to be(true)
    end

    it "fails rather than raises when either side is not a number" do
      expect(call("numeric_equals", "n/a", { "value" => 1 }).detail).to eq("\"n/a\" is not a number")
      expect(call("numeric_equals", "1", { "value" => "n/a" }).detail).to eq("expected \"n/a\" is not a number")
    end
  end
end
