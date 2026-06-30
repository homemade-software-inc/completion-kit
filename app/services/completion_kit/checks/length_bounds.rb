module CompletionKit
  module Checks
    class LengthBounds
      def call(target, config)
        length = target.to_s.length
        min = config["min"] && config["min"].to_i
        max = config["max"] && config["max"].to_i

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
