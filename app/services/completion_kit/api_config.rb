module CompletionKit
  class ApiConfig
    # Configuration class for LLM API credentials
    
    # Get the configuration for the specified model
    # @param model_name [String] The name of the model
    # @return [Hash] Configuration options for the model
    def self.for_model(model_name)
      case model_name
      when /^gpt-/
        {
          api_key: ENV['OPENAI_API_KEY'],
          provider: 'openai'
        }
      when /^claude-/
        {
          api_key: ENV['ANTHROPIC_API_KEY'],
          provider: 'anthropic'
        }
      when /^llama-/
        {
          api_key: ENV['LLAMA_API_KEY'],
          api_endpoint: ENV['LLAMA_API_ENDPOINT'],
          provider: 'llama'
        }
      else
        {}
      end
    end
    
    # Check if the configuration for a model is valid
    # @param model_name [String] The name of the model
    # @return [Boolean] True if valid, false otherwise
    def self.valid_for_model?(model_name)
      client = LlmClient.for_model(model_name, for_model(model_name))
      client.configured?
    end
    
    # Get configuration errors for a model
    # @param model_name [String] The name of the model
    # @return [Array<String>] Array of error messages
    def self.errors_for_model(model_name)
      client = LlmClient.for_model(model_name, for_model(model_name))
      client.configuration_errors
    end
    
    # Get all available models
    # @return [Array<Hash>] Array of model information hashes
    def self.available_models
      [
        { id: 'gpt-4', name: 'GPT-4', provider: 'openai' },
        { id: 'gpt-3.5-turbo', name: 'GPT-3.5 Turbo', provider: 'openai' },
        { id: 'claude-3-opus', name: 'Claude 3 Opus', provider: 'anthropic' },
        { id: 'claude-3-sonnet', name: 'Claude 3 Sonnet', provider: 'anthropic' },
        { id: 'llama-3', name: 'Llama 3', provider: 'llama' }
      ]
    end
  end
end
