module CompletionKit
  module Checks
    module ExpectedResolver
      UNRESOLVED = TargetResolver::UNRESOLVED

      def self.call(response, config)
        TargetResolver.stringify(call_value(response, config))
      end

      def self.call_value(response, config)
        raw = response.expected_output
        return UNRESOLVED if raw.blank?

        path = config["expected_path"].to_s.strip
        return raw if path.empty?

        TargetResolver.dig_json(raw.to_s, path)
      end
    end
  end
end
