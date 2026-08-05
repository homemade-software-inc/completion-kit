require "faraday"
require "faraday/retry"
require "json"

module CompletionKit
  class LlmClient
    DEFAULT_TEMPERATURE = 0.7

    # Providers phrase a temperature refusal every which way. OpenAI's current
    # reasoning models say "Unsupported value: 'temperature' does not support
    # 0.7 with this model. Only the default (1) value is supported.", which
    # shares no wording with Azure's "Unsupported parameter" or Anthropic's
    # "not supported". Matching on any one phrasing silently turns a
    # recoverable refusal into a failed row.
    #
    # The wording can sit on either side of the parameter name, so both orders
    # carry the same phrase set. The gap cannot cross a brace, which keeps a
    # refusal aimed at some other parameter from matching a temperature echoed
    # back in a neighbouring object of the same error body. That would
    # otherwise strip a temperature the model was perfectly happy with and
    # flag the run as having had it ignored.
    REFUSAL_PHRASE = /
      deprecated | not\s+supported | does\s+not\s+support |
      only\s+the\s+default | unsupported\s+(?:parameter|value)
    /xi
    TEMPERATURE_REFUSAL = /
      temperature [^{}]{0,80}? #{REFUSAL_PHRASE}
      |
      #{REFUSAL_PHRASE} [^{}]{0,80}? temperature
    /xi

    def initialize(config = {})
      @config = config
    end

    def temperature_dropped?
      @temperature_dropped == true
    end

    def generate_completion(prompt, options = {})
      raise NotImplementedError, "Subclasses must implement generate_completion"
    end

    def available_models
      raise NotImplementedError, "Subclasses must implement available_models"
    end

    def configured?
      raise NotImplementedError, "Subclasses must implement configured?"
    end

    def configuration_errors
      []
    end

    def self.for_provider(provider_name, config = {})
      case provider_name.to_s
      when "openai"
        OpenAiClient.new(config)
      when "anthropic"
        AnthropicClient.new(config)
      when "ollama"
        OllamaClient.new(config)
      when "openrouter"
        OpenRouterClient.new(config)
      when "azure_foundry"
        AzureFoundryClient.new(config)
      else
        raise ArgumentError, "Unsupported provider: #{provider_name}"
      end
    end

    def self.for_model(model_name, config = {})
      provider = ApiConfig.provider_for_model(model_name)
      raise ArgumentError, "Unsupported model: #{model_name}" unless provider

      for_provider(provider, config)
    end

    protected

    # An explicit nil means the caller wants no temperature sent at all, which
    # is the only request many current models accept. An absent key still gets
    # the historical default.
    def resolve_temperature(options)
      options.key?(:temperature) ? options[:temperature] : DEFAULT_TEMPERATURE
    end

    def temperature_unsupported?(body)
      TEMPERATURE_REFUSAL.match?(body.to_s)
    end

    def build_connection(url, timeout: nil, open_timeout: nil)
      Faraday.new(url: url) do |f|
        f.options.timeout = timeout if timeout
        f.options.open_timeout = open_timeout if open_timeout
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end
    end
  end
end
