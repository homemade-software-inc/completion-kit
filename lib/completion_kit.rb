require "completion_kit/version"
require "completion_kit/engine"

module CompletionKit
  # Configuration for the CompletionKit module
  class Configuration
    attr_accessor :openai_api_key, :anthropic_api_key, :llama_api_key, :llama_api_endpoint
    attr_accessor :judge_model, :high_quality_threshold, :medium_quality_threshold
    
    def initialize
      # API keys
      @openai_api_key = ENV['OPENAI_API_KEY']
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY']
      @llama_api_key = ENV['LLAMA_API_KEY']
      @llama_api_endpoint = ENV['LLAMA_API_ENDPOINT']
      
      # Judge configuration
      @judge_model = 'gpt-4'
      @high_quality_threshold = 80
      @medium_quality_threshold = 50
    end
  end
  
  # Access to the configuration
  class << self
    def config
      @config ||= Configuration.new
    end
    
    def configure
      yield(config) if block_given?
    end
  end
end
