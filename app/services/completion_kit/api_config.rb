module CompletionKit
  class ApiConfig
    def self.for_model(model_name)
      provider = provider_for_model(model_name)
      provider ? for_provider(provider) : {}
    end

    def self.for_provider(provider_name)
      provider = provider_name.to_s
      stored = ProviderCredential.find_by(provider: provider)&.config_hash || {}

      defaults = case provider
                 when "openai"
                   { provider: "openai", api_key: CompletionKit.config.openai_api_key || ENV["OPENAI_API_KEY"] }
                 when "anthropic"
                   { provider: "anthropic", api_key: CompletionKit.config.anthropic_api_key || ENV["ANTHROPIC_API_KEY"] }
                 when "llama"
                   {
                     provider: "llama",
                     api_key: CompletionKit.config.llama_api_key || ENV["LLAMA_API_KEY"],
                     api_endpoint: CompletionKit.config.llama_api_endpoint || ENV["LLAMA_API_ENDPOINT"]
                   }
                 when "openrouter"
                   { provider: "openrouter", api_key: ENV["OPENROUTER_API_KEY"] }
                 else
                   {}
                 end

      defaults.merge(stored.compact)
    end

    def self.provider_for_model(model_name)
      available_match = available_models.find { |model| model[:id] == model_name.to_s }
      return available_match[:provider] if available_match

      case model_name.to_s
      when /\Agpt-/
        "openai"
      when /\Aclaude-/
        "anthropic"
      when /llama/i
        "llama"
      else
        nil
      end
    end

    def self.valid_for_model?(model_name)
      client = LlmClient.for_model(model_name, for_model(model_name))
      client.configured?
    end

    def self.errors_for_model(model_name)
      client = LlmClient.for_model(model_name, for_model(model_name))
      client.configuration_errors
    end

    def self.available_models(provider: nil, scope: :generation)
      query = case scope
              when :judging then Model.for_judging
              when :generation then Model.for_generation
              else Model.active
              end
      query = query.where(provider: provider) if provider.present?
      models = query.order(:provider, :display_name).map do |m|
        { id: m.model_id, name: m.display_name || m.model_id, provider: m.provider }
      end

      return models if models.any?

      configured = ProviderCredential.pluck(:provider)
      providers = provider.present? ? [provider.to_s] : configured
      providers.flat_map do |provider_name|
        next [] unless configured.include?(provider_name)
        client = LlmClient.for_provider(provider_name, for_provider(provider_name))
        client.available_models.map { |model| model.symbolize_keys.merge(provider: provider_name) }
      rescue StandardError
        []
      end.uniq { |model| model[:id] }
    end
  end
end
