module CompletionKit
  module Checks
    class ValidJson
      def call(target, _config)
        JSON.parse(target.to_s)
        Result.new(passed: true, detail: "valid JSON")
      rescue JSON::ParserError
        Result.new(passed: false, detail: "not valid JSON")
      end
    end
  end
end
