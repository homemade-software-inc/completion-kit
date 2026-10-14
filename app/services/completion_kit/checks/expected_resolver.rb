module CompletionKit
  module Checks
    module ExpectedResolver
      UNRESOLVED = TargetResolver::UNRESOLVED

      def self.call(response, config)
        TargetResolver.stringify(resolve(response, config) { |raw| raw.to_s })
      end

      def self.call_value(response, config)
        resolve(response, config) { |raw| parse(raw) }
      end

      def self.resolve(response, config)
        raw = response.expected_output
        return UNRESOLVED if raw.blank?

        path = TargetResolver.normalize_path(config["expected_path"])
        return yield(raw) if path.empty?

        TargetResolver.dig_json(raw.to_s, path)
      end

      def self.parse(raw)
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        raw
      end
    end
  end
end
