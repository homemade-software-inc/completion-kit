# CompletionKit Configuration

# Configure CompletionKit
CompletionKit.configure do |config|
  # 1. Environment variables:
  # config.openai_api_key       = ENV['OPENAI_API_KEY']
  # config.anthropic_api_key    = ENV['ANTHROPIC_API_KEY']
  # config.ollama_api_key       = ENV['OLLAMA_API_KEY']
  # config.ollama_api_endpoint  = ENV['OLLAMA_API_ENDPOINT']

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
  # config.ollama_api_key    = Rails.application.secrets.completion_kit[:ollama_api_key]
  # config.ollama_api_endpoint = Rails.application.secrets.completion_kit[:ollama_api_endpoint]

  # 4. Rails credentials (config/credentials.yml.enc):
  # credentials.yml.enc ->
  # completion_kit:
  #   openai_api_key: 'your-api-key'
  # config.openai_api_key    = Rails.application.credentials.completion_kit[:openai_api_key]
  # config.anthropic_api_key = Rails.application.credentials.completion_kit[:anthropic_api_key]
  # config.ollama_api_key    = Rails.application.credentials.completion_kit[:ollama_api_key]
  # config.ollama_api_endpoint = Rails.application.credentials.completion_kit[:ollama_api_endpoint]

  # 5. Direct assignment:
  # config.openai_api_key = 'your-api-key-here'

  # API Authentication
  # config.api_token = ENV['COMPLETION_KIT_API_TOKEN']

  # API reference page: swap in your own Authentication card (e.g. a multi-tenant
  # token-management panel). The partial receives a `token:` local.
  # config.api_reference_authentication_partial = "my_app/api_token_panel"

  # Web UI Authentication
  # config.username = "admin"
  # config.password = ENV['COMPLETION_KIT_PASSWORD']

  # Reviewer name for verdicts recorded in the web UI. The callable receives the
  # controller. Each reviewer keeps one verdict per response and metric, so return
  # a String unique to the signed-in person. Blank or nil falls back to username,
  # then "operator". Any other return type raises CompletionKit::ConfigurationError.
  # config.current_reviewer = ->(controller) { controller.current_user&.email }
  # Behind a proxy that sets X-Remote-User. Only use this when a trusted proxy
  # always overwrites the header, or any client can claim any name:
  # config.current_reviewer = ->(controller) { controller.request.headers["X-Remote-User"] }

  # Rate limiting (requests per minute, per IP)
  # The REST API and MCP endpoint share api_rate_limit; the web UI uses
  # web_rate_limit. Both are enforced through Rails.cache.
  # config.api_rate_limit = 120
  # config.web_rate_limit = 300
end
