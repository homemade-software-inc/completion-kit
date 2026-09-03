module CompletionKit
  module Checks
    module Textual
      def self.operands(target, config)
        value = config["value"].to_s
        haystack = target.to_s
        return [value.strip, haystack.strip] if Flag.on?(config, "trim")

        [value, haystack]
      end

      def self.include?(haystack, value, config)
        return haystack.include?(value) if Flag.on?(config, "case_sensitive")

        haystack.downcase.include?(value.downcase)
      end
    end
  end
end
