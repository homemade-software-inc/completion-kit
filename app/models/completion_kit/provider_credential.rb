module CompletionKit
  class ProviderCredential < ApplicationRecord
    PROVIDERS = %w[openai anthropic llama].freeze
    PROVIDER_LABELS = { "openai" => "OpenAI", "anthropic" => "Anthropic", "llama" => "Llama" }.freeze

    def as_json(options = {})
      {
        id: id, provider: provider, api_endpoint: api_endpoint,
        created_at: created_at, updated_at: updated_at
      }
    end

    def display_provider
      PROVIDER_LABELS[provider] || provider.titleize
    end

    validates :provider, presence: true, inclusion: { in: PROVIDERS }, uniqueness: true

    def config_hash
      {
        provider: provider,
        api_key: api_key,
        api_endpoint: api_endpoint
      }.compact
    end

    def available_models
      LlmClient.for_provider(provider, config_hash).available_models
    rescue StandardError
      []
    end

    def configured?
      LlmClient.for_provider(provider, config_hash).configured?
    rescue StandardError
      false
    end
  end
end
