module CompletionKit
  class Error < StandardError; end

  class ConfigurationError < Error; end

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
