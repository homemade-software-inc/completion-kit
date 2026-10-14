module CompletionKit
  module Checks
    module Labels
      KINDS = {
        "contains" => "Contains a phrase",
        "not_contains" => "Does not contain a phrase",
        "equals" => "Equals exactly",
        "regex" => "Matches a pattern",
        "valid_json" => "Is valid JSON",
        "json_path_equals" => "A JSON field equals a value",
        "length_bounds" => "Length is within a range",
        "list_overlap" => "How much of a list was found",
        "numeric_bounds" => "A number is within a range",
        "numeric_equals" => "A number is close enough"
      }.freeze

      TARGETS = {
        "response_text" => "The response text",
        "input_data" => "The input row",
        "json_path" => "A value from the response JSON"
      }.freeze

      COMPARE_TO = {
        "constant" => "A value you type",
        "expected" => "Each row's expected value"
      }.freeze

      SCORE_BY = {
        "recall" => "How much of the expected list was found",
        "precision" => "How much of the answer belonged",
        "f1" => "A balance of the two",
        "jaccard" => "How much the two lists overlap"
      }.freeze

      FIELDS = {
        "check_kind" => "Rule",
        "target" => "What to check",
        "target_path" => "Path into the JSON",
        "compare_to" => "Compare against",
        "value" => "Text to look for",
        "pattern" => "Pattern",
        "json_path" => "JSON path",
        "expected" => "Expected value",
        "expected_path" => "Field in the answer key",
        "score_by" => "How to score it",
        "min" => "Minimum",
        "max" => "Maximum",
        "tolerance" => "How far off is still right",
        "case_sensitive" => "Case sensitive",
        "multiline" => "Multiline",
        "trim" => "Trim whitespace"
      }.freeze

      FIELDS_BY_KIND = {
        "length_bounds" => { "min" => "Shortest allowed", "max" => "Longest allowed" },
        "numeric_bounds" => { "min" => "Lowest allowed", "max" => "Highest allowed" },
        "list_overlap" => { "min" => "Lowest score that passes", "value" => "Expected list" },
        "numeric_equals" => { "value" => "Expected number" }
      }.freeze

      HINTS = {
        "min" => "Leave blank for no minimum.",
        "max" => "Leave blank for no maximum."
      }.freeze

      HINTS_BY_KIND = {
        "list_overlap" => { "min" => "Leave blank to require a perfect score." }
      }.freeze

      VALUES = { "compare_to" => COMPARE_TO, "score_by" => SCORE_BY }.freeze

      def self.kind(kind)
        KINDS.fetch(kind.to_s) { kind.to_s.humanize }
      end

      def self.target(target)
        TARGETS.fetch(target.to_s) { target.to_s.humanize }
      end

      def self.field(key, kind = nil)
        FIELDS_BY_KIND.dig(kind.to_s, key.to_s) || FIELDS.fetch(key.to_s) { key.to_s.humanize }
      end

      def self.hint(key, kind = nil)
        HINTS_BY_KIND.dig(kind.to_s, key.to_s) || HINTS[key.to_s]
      end

      def self.value(key, value)
        VALUES.fetch(key.to_s, {}).fetch(value.to_s, value)
      end

      def self.worded?(key)
        VALUES.key?(key.to_s)
      end

      def self.in_form_order(config)
        order = FIELDS.keys
        config.sort_by.with_index { |(key, _value), index| [order.index(key) || order.length, index] }.to_h
      end
    end
  end
end
