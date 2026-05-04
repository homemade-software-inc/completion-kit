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
end
