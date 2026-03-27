CompletionKit.configure do |config|
  config.api_token = ENV["COMPLETION_KIT_API_TOKEN"]
  if ENV["COMPLETION_KIT_PASSWORD"].present?
    config.username = ENV.fetch("COMPLETION_KIT_USERNAME", "admin")
    config.password = ENV["COMPLETION_KIT_PASSWORD"]
    config.auth_strategy = ->(controller) {
      unless controller.session[:authenticated]
        controller.redirect_to controller.main_app.login_path
      end
    }
  end
end

Rails.application.config.after_initialize do
  {
    "openai" => ENV["OPENAI_API_KEY"],
    "anthropic" => ENV["ANTHROPIC_API_KEY"],
    "llama" => ENV["LLAMA_API_KEY"]
  }.each do |provider, key|
    next unless key.present?
    cred = CompletionKit::ProviderCredential.find_or_initialize_by(provider: provider)
    cred.api_key = key
    cred.api_endpoint = ENV["LLAMA_API_ENDPOINT"] if provider == "llama"
    cred.save!
  end
rescue ActiveRecord::StatementInvalid
end
