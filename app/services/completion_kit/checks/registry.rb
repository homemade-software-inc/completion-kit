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
      FLAG_KEYS = %w[case_sensitive multiline trim].freeze
      NUMBER_KEYS = %w[min max tolerance].freeze
      DEFAULTS = { "target" => "response_text", "score_by" => ListOverlap::DEFAULT_MEASURE }.freeze

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

      def self.unused_keys(config)
        kind = config["check_kind"]
        keys = config["compare_to"] == "expected" && compares_value?(kind) ? [expected_key(kind)] : %w[compare_to expected_path]
        config["target"] == "json_path" ? keys : keys + %w[target_path]
      end

      def self.canonical(config)
        hash = config.to_h.stringify_keys
        relevant = hash.slice(*SHARED_KEYS, *config_keys(hash["check_kind"])).except(*unused_keys(hash))
        relevant.to_h { |key, value| [key, canonical_value(key, value)] }.reject { |key, value| omitted?(key, value) }
      end

      def self.canonical_value(key, value)
        case key
        when *FLAG_KEYS then Flag.cast(value)
        when *NUMBER_KEYS then NumericValue.parse(value) || value
        when "value" then canonical_operand(value)
        when "expected" then value.is_a?(String) ? parse_json(value) : value
        else value
        end
      end

      def self.canonical_operand(value)
        return value.to_s if value.is_a?(::Numeric)
        return value unless value.is_a?(String)

        parsed = parse_json(value)
        parsed.is_a?(Array) ? parsed : value
      end

      def self.parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        text
      end

      def self.omitted?(key, value)
        value.nil? || value == "" || (FLAG_KEYS.include?(key) && !value) || DEFAULTS[key] == value
      end
    end
  end
end
