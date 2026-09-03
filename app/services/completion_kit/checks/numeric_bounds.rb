module CompletionKit
  module Checks
    class NumericBounds
      def call(target, config)
        number = NumericValue.parse(target)
        return Result.new(passed: false, detail: "#{target.inspect} is not a number") if number.nil?

        min = NumericValue.parse(config["min"])
        max = NumericValue.parse(config["max"])
        shown = NumericValue.format(number)

        if min && number < min
          Result.new(passed: false, detail: "#{shown} is below min #{NumericValue.format(min)}")
        elsif max && number > max
          Result.new(passed: false, detail: "#{shown} is above max #{NumericValue.format(max)}")
        else
          Result.new(passed: true, detail: "#{shown} is within bounds")
        end
      end
    end
  end
end
