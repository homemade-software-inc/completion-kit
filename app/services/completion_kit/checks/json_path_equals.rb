module CompletionKit
  module Checks
    class JsonPathEquals
      MISSING = Object.new

      def call(target, config)
        parsed = JSON.parse(target.to_s)
        value = dig(parsed, config["json_path"].to_s)

        if value.equal?(MISSING)
          Result.new(passed: false, detail: "path #{config["json_path"]} not found")
        elsif value == config["expected"]
          Result.new(passed: true, detail: "#{config["json_path"]} == #{config["expected"].inspect}")
        else
          Result.new(passed: false, detail: "#{config["json_path"]} was #{value.inspect}, expected #{config["expected"].inspect}")
        end
      rescue JSON::ParserError
        Result.new(passed: false, detail: "not valid JSON")
      end

      private

      def dig(data, path)
        path.split(".").reduce(data) do |node, key|
          return MISSING unless node.is_a?(Hash) && node.key?(key)

          node[key]
        end
      end
    end
  end
end
