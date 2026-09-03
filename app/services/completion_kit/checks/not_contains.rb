module CompletionKit
  module Checks
    class NotContains
      def call(target, config)
        value, haystack = Textual.operands(target, config)

        if Textual.include?(haystack, value, config)
          Result.new(passed: false, detail: "contains #{value.inspect}")
        else
          Result.new(passed: true, detail: "does not contain #{value.inspect}")
        end
      end
    end
  end
end
