module CompletionKit
  module Checks
    class LengthBounds
      def call(target, config)
        length = target.to_s.length
        min = config["min"]
        max = config["max"]

        if min && length < min
          Result.new(passed: false, detail: "length #{length} below min #{min}")
        elsif max && length > max
          Result.new(passed: false, detail: "length #{length} above max #{max}")
        else
          Result.new(passed: true, detail: "length #{length} within bounds")
        end
      end
    end
  end
end
