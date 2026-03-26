CompletionKit.configure do |config|
  config.api_token = ENV["COMPLETION_KIT_API_TOKEN"]
  if ENV["COMPLETION_KIT_PASSWORD"]
    config.username = ENV.fetch("COMPLETION_KIT_USERNAME", "admin")
    config.password = ENV["COMPLETION_KIT_PASSWORD"]
  end
end
