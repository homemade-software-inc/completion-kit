module CompletionKit
  class ApiConfig
    PROVIDERS = %w[openai anthropic ollama openrouter].freeze

    def self.for_model(model_name)
      provider = provider_for_model(model_name)
      provider ? for_provider(provider) : {}
    end

    def self.for_provider(provider_name)
      provider = provider_name.to_s
      stored = ProviderCredential.find_by(provider: provider)&.config_hash || {}

      defaults = if CompletionKit.config.tenant_scope
                   PROVIDERS.include?(provider) ? { provider: provider } : {}
                 else
                   case provider
                   when "openai"
                     { provider: "openai", api_key: CompletionKit.config.openai_api_key || ENV["OPENAI_API_KEY"] }
                   when "anthropic"
                     { provider: "anthropic", api_key: CompletionKit.config.anthropic_api_key || ENV["ANTHROPIC_API_KEY"] }
                   when "ollama"
                     {
                       provider: "ollama",
                       api_key: CompletionKit.config.ollama_api_key || ENV["OLLAMA_API_KEY"],
                       api_endpoint: CompletionKit.config.ollama_api_endpoint || ENV["OLLAMA_API_ENDPOINT"]
                     }
                   when "openrouter"
                     { provider: "openrouter", api_key: ENV["OPENROUTER_API_KEY"] }
                   else
                     {}
                   end
                 end

      defaults.merge(stored.compact)
    end

    def self.provider_for_model(model_name)
      available_match = available_models.find { |model| model[:id] == model_name.to_s }
      return available_match[:provider] if available_match

      guess = case model_name.to_s
              when /\Agpt-/ then "openai"
              when /\Aclaude-/ then "anthropic"
              end
      configured = ProviderCredential.distinct.pluck(:provider)
      return guess if configured.empty?

      guess if guess && configured.include?(guess)
    end

    def self.default_judge_model
      configured = CompletionKit.config.judge_model
      configured = configured.call if configured.respond_to?(:call)
      configured.presence || Model.for_judging.order(:provider, :display_name).first&.model_id
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
        entry = { id: m.model_id, name: m.display_name || m.model_id, provider: m.provider }
        entry[:judging_confirmed] = !m.supports_judging.nil? if scope == :judging
        entry
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
