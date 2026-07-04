module CompletionKit
  module Checks
    module ExpectedResolver
      UNRESOLVED = TargetResolver::UNRESOLVED

      def self.call(response, config)
        raw = response.expected_output
        return UNRESOLVED if raw.blank?

        path = config["expected_path"].to_s.strip
        return raw.to_s if path.empty?

        TargetResolver.resolve_json_path(raw.to_s, path)
      end
    end
  end
end
