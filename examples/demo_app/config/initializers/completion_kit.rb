# CompletionKit Configuration

# Configure CompletionKit
CompletionKit.configure do |config|
  # 1. Environment variables:
  # config.openai_api_key       = ENV['OPENAI_API_KEY']
  # config.anthropic_api_key    = ENV['ANTHROPIC_API_KEY']
  # config.llama_api_key        = ENV['LLAMA_API_KEY']
  # config.llama_api_endpoint   = ENV['LLAMA_API_ENDPOINT']

  # 2. Dotenv (.env file):
  # require 'dotenv/load'
  # config.openai_api_key = ENV['OPENAI_API_KEY'] if ENV['OPENAI_API_KEY']

  # 3. Rails secrets (config/secrets.yml):
  # secrets.yml ->
  # development:
  #   completion_kit:
  #     openai_api_key: 'your-api-key'
  # config.openai_api_key    = Rails.application.secrets.completion_kit[:openai_api_key]
  # config.anthropic_api_key = Rails.application.secrets.completion_kit[:anthropic_api_key]
  # config.llama_api_key     = Rails.application.secrets.completion_kit[:llama_api_key]
  # config.llama_api_endpoint= Rails.application.secrets.completion_kit[:llama_api_endpoint]

  # 4. Rails credentials (config/credentials.yml.enc):
  # credentials.yml.enc ->
  # completion_kit:
  #   openai_api_key: 'your-api-key'
  # config.openai_api_key    = Rails.application.credentials.completion_kit[:openai_api_key]
  # config.anthropic_api_key = Rails.application.credentials.completion_kit[:anthropic_api_key]
  # config.llama_api_key     = Rails.application.credentials.completion_kit[:llama_api_key]
  # config.llama_api_endpoint= Rails.application.credentials.completion_kit[:llama_api_endpoint]

  # 5. Direct assignment:
  # config.openai_api_key = 'your-api-key-here'
end
