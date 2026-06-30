module CompletionKit
  module Checks
    module TargetResolver
      TARGETS = %w[response_text input_data json_path].freeze
      UNRESOLVED = Object.new.freeze

      def self.call(response, config)
        case config["target"]
        when "input_data"
          response.input_data
        when "json_path"
          resolve_json_path(response.response_text, config["target_path"].to_s)
        else
          response.response_text
        end
      end

      def self.resolve_json_path(text, path)
        parsed = JSON.parse(text.to_s)
        value = path.split(".").reduce(parsed) do |node, key|
          return UNRESOLVED unless node.is_a?(Hash) && node.key?(key)

          node[key]
        end
        value.to_s
      rescue JSON::ParserError
        UNRESOLVED
      end
    end
  end
end
