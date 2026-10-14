module CompletionKit
  module Checks
    class JsonPathEquals
      def call(target, config)
        value = TargetResolver.walk(JSON.parse(target.to_s), config["json_path"])

        if value.equal?(TargetResolver::UNRESOLVED)
          Result.new(passed: false, detail: "path #{config["json_path"]} not found")
        elsif value == config["expected"]
          Result.new(passed: true, detail: "#{config["json_path"]} == #{config["expected"].inspect}")
        else
          Result.new(passed: false, detail: "#{config["json_path"]} was #{value.inspect}, expected #{config["expected"].inspect}")
        end
      rescue JSON::ParserError
        Result.new(passed: false, detail: "not valid JSON")
      end
    end
  end
end
