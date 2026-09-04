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
        "list_overlap" => ListOverlap,
        "numeric_bounds" => NumericBounds,
        "numeric_equals" => NumericEquals
      }.freeze

      REQUIRED_KEYS = {
        "contains" => %w[value],
        "not_contains" => %w[value],
        "equals" => %w[value],
        "regex" => %w[pattern],
        "valid_json" => [],
        "json_path_equals" => %w[json_path expected],
        "length_bounds" => [],
        "list_overlap" => %w[value],
        "numeric_bounds" => [],
        "numeric_equals" => %w[value]
      }.freeze

      CONFIG_KEYS = {
        "contains" => %w[value case_sensitive trim],
        "not_contains" => %w[value case_sensitive trim],
        "equals" => %w[value case_sensitive trim],
        "regex" => %w[pattern case_sensitive multiline],
        "valid_json" => [],
        "json_path_equals" => %w[json_path expected],
        "length_bounds" => %w[min max],
        "list_overlap" => %w[value score_by min case_sensitive],
        "numeric_bounds" => %w[min max],
        "numeric_equals" => %w[value tolerance]
      }.freeze

      SHARED_KEYS = %w[check_kind target target_path compare_to expected_path].freeze

      EXPECTED_KEYS = {
        "contains" => "value",
        "not_contains" => "value",
        "equals" => "value",
        "json_path_equals" => "expected",
        "list_overlap" => "value",
        "numeric_equals" => "value"
      }.freeze

      RAW_TARGET_KINDS = %w[list_overlap numeric_bounds numeric_equals].freeze
      RAW_EXPECTED_KINDS = %w[json_path_equals list_overlap numeric_equals].freeze
      BOUNDED_KINDS = %w[length_bounds numeric_bounds].freeze
      SCORING_KINDS = %w[list_overlap].freeze

      KINDS = CHECKS.keys.freeze

      def self.kinds
        KINDS
      end

      def self.required_keys
        REQUIRED_KEYS
      end

      def self.config_keys(kind)
        CONFIG_KEYS.fetch(kind, [])
      end

      def self.compares_value?(kind)
        EXPECTED_KEYS.key?(kind)
      end

      def self.expected_key(kind)
        EXPECTED_KEYS[kind]
      end

      def self.comparable_kinds
        EXPECTED_KEYS.keys
      end

      def self.raw_target?(kind)
        RAW_TARGET_KINDS.include?(kind)
      end

      def self.raw_expected?(kind)
        RAW_EXPECTED_KINDS.include?(kind)
      end

      def self.bounded?(kind)
        BOUNDED_KINDS.include?(kind)
      end

      def self.scores?(kind)
        SCORING_KINDS.include?(kind)
      end

      def self.fetch(kind)
        CHECKS.fetch(kind).new
      end
    end
  end
end
