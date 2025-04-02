module CompletionKit
  class LlmClient
    # Base class for LLM API clients
    # This class defines the interface for all LLM API clients
    
    # Initialize the client with configuration
    # @param config [Hash] Configuration options
    def initialize(config = {})
      @config = config
    end
    
    # Generate a completion for the given prompt
    # @param prompt [String] The prompt to generate a completion for
    # @param options [Hash] Additional options for the completion
    # @return [String] The generated completion
    def generate_completion(prompt, options = {})
      raise NotImplementedError, "Subclasses must implement generate_completion"
    end
    
    # Get the available models for this client
    # @return [Array<Hash>] Array of model information hashes
    def available_models
      raise NotImplementedError, "Subclasses must implement available_models"
    end
    
    # Check if the client is properly configured
    # @return [Boolean] True if configured, false otherwise
    def configured?
      raise NotImplementedError, "Subclasses must implement configured?"
    end
    
    # Get configuration errors if any
    # @return [Array<String>] Array of error messages
    def configuration_errors
      []
    end
    
    # Factory method to create a client for the given model
    # @param model_name [String] The name of the model to create a client for
    # @param config [Hash] Configuration options
    # @return [LlmClient] An instance of the appropriate client
    def self.for_model(model_name, config = {})
      case model_name
      when /^gpt-/
        OpenAiClient.new(config)
      when /^claude-/
        AnthropicClient.new(config)
      when /^llama-/
        LlamaClient.new(config)
      else
        raise ArgumentError, "Unsupported model: #{model_name}"
      end
    end
  end
end
