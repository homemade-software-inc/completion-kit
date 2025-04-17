# CompletionKit Configuration

# Configure CompletionKit
CompletionKit.configure do |config|
  # API Keys for LLM providers
  # Replace these with your actual API keys or use environment variables
  
  # OpenAI API Key (for GPT models)
  config.openai_api_key = ENV['OPENAI_API_KEY']
  
  # Anthropic API Key (for Claude models)
  config.anthropic_api_key = ENV['ANTHROPIC_API_KEY']
  
  # Llama API Key and Endpoint
  config.llama_api_key = ENV['LLAMA_API_KEY']
  config.llama_api_endpoint = ENV['LLAMA_API_ENDPOINT']
  
  # You can set specific keys directly if needed
  # config.openai_api_key = 'your-api-key-here'
end

# Load keys from .env file if available
if defined?(Dotenv) && File.exist?(Rails.root.join('.env'))
  require 'dotenv/load'
  
  # Reload configuration after dotenv loads
  CompletionKit.configure do |config|
    config.openai_api_key = ENV['OPENAI_API_KEY'] if ENV['OPENAI_API_KEY']
    config.anthropic_api_key = ENV['ANTHROPIC_API_KEY'] if ENV['ANTHROPIC_API_KEY']
    config.llama_api_key = ENV['LLAMA_API_KEY'] if ENV['LLAMA_API_KEY']
    config.llama_api_endpoint = ENV['LLAMA_API_ENDPOINT'] if ENV['LLAMA_API_ENDPOINT']
  end
end
