module CompletionKit
  module Checks
    class NumericEquals
      PERCENT = /\A(.*)%\z/

      def call(target, config)
        actual = NumericValue.decimal(target)
        return Result.new(passed: false, detail: "#{NumericValue.preview(target)} is not a number") if actual.nil?

        expected = NumericValue.decimal(config["value"])
        return Result.new(passed: false, detail: "expected #{NumericValue.preview(config["value"])} is not a number") if expected.nil?

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
        return (NumericValue.decimal(share[1]) || BigDecimal("0")) / 100 * expected.abs if share

        NumericValue.decimal(raw) || BigDecimal("0")
      end

      def self.tolerance_value(raw)
        share = PERCENT.match(raw.to_s)
        NumericValue.parse(share ? share[1] : raw)
      end
    end
  end
end
