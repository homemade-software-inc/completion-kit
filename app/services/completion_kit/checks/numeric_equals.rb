module CompletionKit
  module Checks
    class NumericEquals
      MODES = %w[absolute relative].freeze
      RELATIVE = "relative".freeze

      def call(target, config)
        actual = NumericValue.parse(target)
        return Result.new(passed: false, detail: "#{target.inspect} is not a number") if actual.nil?

        expected = NumericValue.parse(config["value"])
        return Result.new(passed: false, detail: "expected #{config["value"].inspect} is not a number") if expected.nil?

        difference = (actual - expected).abs
        allowed = allowance(config, expected)
        shown = "#{NumericValue.format(actual)} vs #{NumericValue.format(expected)}"

        if difference <= allowed
          Result.new(passed: true, detail: "#{shown}, within #{NumericValue.format(allowed)}")
        else
          Result.new(passed: false, detail: "#{shown}, off by #{NumericValue.format(difference)} (allowed #{NumericValue.format(allowed)})")
        end
      end

      private

      def allowance(config, expected)
        tolerance = NumericValue.parse(config["tolerance"]) || 0.0
        config["tolerance_mode"] == RELATIVE ? tolerance * expected.abs : tolerance
      end
    end
  end
end
