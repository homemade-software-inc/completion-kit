module CompletionKit
  class LlmClient
    def initialize(config = {})
      @config = config
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
      when "llama"
        LlamaClient.new(config)
      else
        raise ArgumentError, "Unsupported provider: #{provider_name}"
      end
    end

    def self.for_model(model_name, config = {})
      provider = ApiConfig.provider_for_model(model_name)
      raise ArgumentError, "Unsupported model: #{model_name}" unless provider

      for_provider(provider, config)
    end
  end
end
