module CompletionKit
  module Checks
    module Registry
      CHECKS = {
        "contains" => Contains,
        "not_contains" => NotContains,
        "equals" => Equals,
        "regex" => Regex,
        "valid_json" => ValidJson,
        "json_path_equals" => JsonPathEquals,
        "length_bounds" => LengthBounds,
        "no_refusal" => NoRefusal
      }.freeze

      REQUIRED_KEYS = {
        "contains" => %w[value],
        "not_contains" => %w[value],
        "equals" => %w[value],
        "regex" => %w[pattern],
        "valid_json" => [],
        "json_path_equals" => %w[json_path expected],
        "length_bounds" => [],
        "no_refusal" => []
      }.freeze

      KINDS = CHECKS.keys.freeze

      def self.kinds
        KINDS
      end

      def self.required_keys
        REQUIRED_KEYS
      end

      def self.fetch(kind)
        CHECKS.fetch(kind).new
      end
    end
  end
end
