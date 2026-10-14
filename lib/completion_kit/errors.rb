require "faraday"
require "json"

module CompletionKit
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class EndpointError < Error
    CONNECTION_MESSAGE = "Could not connect to the endpoint."
    NOT_JSON_MESSAGE = "The endpoint did not return JSON."

    def self.from(error)
      message = case error
                when Faraday::Error then CONNECTION_MESSAGE
                when JSON::ParserError then NOT_JSON_MESSAGE
                end
      return error unless message

      Rails.logger.warn("[CompletionKit] endpoint request failed: #{error.class}: #{error.message}")
      new(message)
    end
  end

  class RateLimitError < Error
    attr_reader :provider, :status, :retry_after

    def initialize(message = nil, provider: nil, status: nil, retry_after: nil)
      super(message)
      @provider = provider
      @status = status
      @retry_after = retry_after
    end
  end

  class ProviderError < Error
    attr_reader :status

    def initialize(message = nil, status: nil)
      super(message)
      @status = status
    end

    def self.from_client_error(text)
      detail = text.to_s.sub(/\AError:\s*/, "")
      if (match = detail.match(/\A(\d{3})\s*-\s*(.*)/m))
        new(match[2], status: match[1].to_i)
      else
        new(detail)
      end
    end
  end
end
