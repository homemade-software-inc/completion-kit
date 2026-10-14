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

      FIELDS = {
        "check_kind" => "Rule",
        "target" => "What to check",
        "value" => "Text to look for",
        "pattern" => "Pattern",
        "json_path" => "JSON path",
        "expected" => "Expected value",
        "expected_path" => "Field in the answer key",
        "compare_to" => "Compare against",
        "target_path" => "Path into the JSON",
        "min" => "Minimum",
        "max" => "Maximum",
        "score_by" => "How to score it",
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

      def self.kind(kind)
        KINDS.fetch(kind.to_s) { kind.to_s.humanize }
      end

      def self.field(key, kind = nil)
        FIELDS_BY_KIND.dig(kind.to_s, key.to_s) || FIELDS.fetch(key.to_s) { key.to_s.humanize }
      end
    end
  end
end
