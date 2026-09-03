module CompletionKit
  module Checks
    class Contains
      def call(target, config)
        value, haystack = Textual.operands(target, config)

        if Textual.include?(haystack, value, config)
          Result.new(passed: true, detail: "contains #{value.inspect}")
        else
          Result.new(passed: false, detail: "does not contain #{value.inspect}")
        end
      end
    end
  end
end
