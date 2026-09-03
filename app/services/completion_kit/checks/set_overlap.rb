module CompletionKit
  module Checks
    class SetOverlap
      MEASURES = %w[recall precision f1 jaccard].freeze
      DEFAULT_MEASURE = "recall".freeze
      DEFAULT_MIN = 1.0
      SEPARATORS = /[,;\n]/
      DECORATION = /\A(?:["'`]+|[-*•]\s+)|["'`]+\z/

      def call(target, config)
        actual = to_set(target, config)
        expected = to_set(config["value"], config)
        measure = MEASURES.include?(config["measure"]) ? config["measure"] : DEFAULT_MEASURE
        overlap = (actual & expected).length
        score = score_for(measure, overlap, actual.length, expected.length).round(4)
        threshold = NumericValue.parse(config["min"]) || DEFAULT_MIN

        Result.new(
          passed: score >= threshold,
          detail: "#{measure} #{score} (#{overlap} of #{expected.length} expected, #{actual.length} returned)",
          score: score
        )
      end

      private

      def score_for(measure, overlap, actual_size, expected_size)
        return 1.0 if actual_size.zero? && expected_size.zero?

        case measure
        when "precision" then ratio(overlap, actual_size)
        when "jaccard" then ratio(overlap, actual_size + expected_size - overlap)
        when "f1" then f1(ratio(overlap, actual_size), ratio(overlap, expected_size))
        else ratio(overlap, expected_size)
        end
      end

      def ratio(numerator, denominator)
        return 0.0 if denominator.zero?

        numerator.to_f / denominator
      end

      def f1(precision, recall)
        return 0.0 if (precision + recall).zero?

        (2 * precision * recall) / (precision + recall)
      end

      def to_set(value, config)
        items = coerce_list(value).map { |item| normalize(item, config) }
        items.reject(&:empty?).uniq
      end

      def normalize(item, config)
        text = item.to_s.strip.gsub(DECORATION, "").strip
        Flag.on?(config, "case_sensitive") ? text : text.downcase
      end

      def coerce_list(value)
        case value
        when Array then value
        when Hash, nil then []
        else
          text = value.to_s.strip
          return [] if text.empty?

          from_json(text) || text.split(SEPARATORS)
        end
      end

      def from_json(text)
        parsed = JSON.parse(text)
        return parsed if parsed.is_a?(Array)
        return parsed.split(SEPARATORS) if parsed.is_a?(String)
        return [] if parsed.is_a?(Hash)

        nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end
