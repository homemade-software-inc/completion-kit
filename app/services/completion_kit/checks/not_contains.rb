module CompletionKit
  module Checks
    class NotContains
      def call(target, config)
        value = config["value"].to_s
        haystack = target.to_s
        present = if config["case_sensitive"] == true
          haystack.include?(value)
        else
          haystack.downcase.include?(value.downcase)
        end

        if present
          Result.new(passed: false, detail: "contains #{value.inspect}")
        else
          Result.new(passed: true, detail: "does not contain #{value.inspect}")
        end
      end
    end
  end
end
