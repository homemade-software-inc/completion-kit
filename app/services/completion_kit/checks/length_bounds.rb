module CompletionKit
  module Checks
    class LengthBounds
      def call(target, config)
        length = target.to_s.length
        min = NumericValue.parse(config["min"])
        max = NumericValue.parse(config["max"])

        if min && length < min
          Result.new(passed: false, detail: "length #{length} below min #{NumericValue.format(min)}")
        elsif max && length > max
          Result.new(passed: false, detail: "length #{length} above max #{NumericValue.format(max)}")
        else
          Result.new(passed: true, detail: "length #{length} within bounds")
        end
      end
    end
  end
end
