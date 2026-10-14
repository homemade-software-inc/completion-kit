require "json"

module CompletionKit
  module JsonObject
    module_function

    def parse(text)
      data = JSON.parse(text)
      raise JSON::ParserError, "expected a JSON object, got #{data.class}" unless data.is_a?(Hash)

      data
    end
  end
end
