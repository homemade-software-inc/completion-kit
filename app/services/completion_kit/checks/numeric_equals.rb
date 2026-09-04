module CompletionKit
  module Checks
    class NumericEquals
      PERCENT = /\A(.*)%\z/

      def call(target, config)
        actual = NumericValue.parse(target)
        return Result.new(passed: false, detail: "#{target.inspect} is not a number") if actual.nil?

        expected = NumericValue.parse(config["value"])
        return Result.new(passed: false, detail: "expected #{config["value"].inspect} is not a number") if expected.nil?

        difference = (actual - expected).abs
        allowed = self.class.allowance(config["tolerance"], expected)
        shown = "#{NumericValue.format(actual)} vs #{NumericValue.format(expected)}"

        if difference <= allowed
          Result.new(passed: true, detail: "#{shown}, within #{NumericValue.format(allowed)}")
        else
          Result.new(passed: false, detail: "#{shown}, off by #{NumericValue.format(difference)} (allowed #{NumericValue.format(allowed)})")
        end
      end

      def self.allowance(raw, expected)
        share = PERCENT.match(raw.to_s)
        return (NumericValue.parse(share[1]) || 0.0) / 100.0 * expected.abs if share

        NumericValue.parse(raw) || 0.0
      end

      def self.tolerance_value(raw)
        share = PERCENT.match(raw.to_s)
        NumericValue.parse(share ? share[1] : raw)
      end
    end
  end
end
