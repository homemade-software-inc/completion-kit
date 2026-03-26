CompletionKit.configure do |config|
  config.api_token = ENV["COMPLETION_KIT_API_TOKEN"]
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.llama_api_key = ENV["LLAMA_API_KEY"]
  config.llama_api_endpoint = ENV["LLAMA_API_ENDPOINT"]
  if ENV["COMPLETION_KIT_PASSWORD"]
    config.username = ENV.fetch("COMPLETION_KIT_USERNAME", "admin")
    config.password = ENV["COMPLETION_KIT_PASSWORD"]
  end
end
