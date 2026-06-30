module CompletionKit
  module Checks
    class Regex
      def call(target, config)
        options = 0
        options |= Regexp::IGNORECASE if config["case_sensitive"] == false
        options |= Regexp::MULTILINE if config["multiline"] == true
        pattern = Regexp.new(config["pattern"].to_s, options)

        if pattern.match?(target.to_s)
          Result.new(passed: true, detail: "matched /#{config["pattern"]}/")
        else
          Result.new(passed: false, detail: "no match for /#{config["pattern"]}/")
        end
      rescue RegexpError => e
        Result.new(passed: false, detail: "invalid pattern: #{e.message}")
      end
    end
  end
end
