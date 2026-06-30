module CompletionKit
  module Checks
    class NoRefusal
      PATTERNS = [
        /\bi'?m sorry\b/i,
        /\bi can'?t (?:help|assist|comply|do that|provide)/i,
        /\bi (?:cannot|can'?t) (?:help|assist|fulfill|comply|provide)/i,
        /\bi'?m (?:unable|not able) to\b/i,
        /\bi (?:won'?t|will not) (?:be able|help|assist)\b/i,
        /\bas an ai\b/i
      ].freeze

      def call(target, _config)
        text = target.to_s
        if PATTERNS.any? { |pattern| pattern.match?(text) }
          Result.new(passed: false, detail: "refusal detected")
        else
          Result.new(passed: true, detail: "no refusal detected")
        end
      end
    end
  end
end
