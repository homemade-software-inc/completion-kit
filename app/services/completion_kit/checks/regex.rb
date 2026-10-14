module CompletionKit
  module Checks
    class Regex
      def self.build(config)
        options = 0
        options |= Regexp::IGNORECASE unless Flag.on?(config, "case_sensitive")
        options |= Regexp::MULTILINE if Flag.on?(config, "multiline")
        Regexp.new(config["pattern"].to_s, options, timeout: CompletionKit.config.regex_timeout)
      end

      def call(target, config)
        pattern = self.class.build(config)

        if pattern.match?(target.to_s)
          Result.new(passed: true, detail: "matched /#{config["pattern"]}/")
        else
          Result.new(passed: false, detail: "no match for /#{config["pattern"]}/")
        end
      rescue Regexp::TimeoutError
        Result.new(passed: false, detail: "timed out after #{pattern.timeout || Regexp.timeout}s matching /#{config["pattern"]}/")
      rescue RegexpError => e
        Result.new(passed: false, detail: "invalid pattern: #{e.message}")
      end
    end
  end
end
