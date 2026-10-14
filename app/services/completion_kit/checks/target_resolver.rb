module CompletionKit
  module Checks
    module TargetResolver
      TARGETS = %w[response_text input_data json_path].freeze
      UNRESOLVED = Object.new.freeze
      ARRAY_INDEX = /\A\d+\z/
      ROOT = /\A\$\.?/

      def self.call(response, config)
        stringify(call_value(response, config))
      end

      def self.call_value(response, config)
        case config["target"]
        when "input_data"
          response.input_data
        when "json_path"
          dig_json(response.response_text, config["target_path"])
        else
          response.response_text
        end
      end

      def self.dig_json(text, path)
        walk(JSON.parse(text.to_s), path)
      rescue JSON::ParserError
        UNRESOLVED
      end

      def self.walk(document, path)
        normalize_path(path).split(".").reduce(document) do |node, key|
          case node
          when Hash
            return UNRESOLVED unless node.key?(key)

            node[key]
          when Array
            index = array_index(node, key)
            return UNRESOLVED if index.nil?

            node[index]
          else
            return UNRESOLVED
          end
        end
      end

      def self.normalize_path(path)
        path.to_s.strip.sub(ROOT, "")
      end

      def self.array_index(array, key)
        return nil unless ARRAY_INDEX.match?(key)

        index = key.to_i
        index < array.length ? index : nil
      end

      def self.stringify(value)
        return value if value.equal?(UNRESOLVED)

        value.to_s
      end
    end
  end
end
