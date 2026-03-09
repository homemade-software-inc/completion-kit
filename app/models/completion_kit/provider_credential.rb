module CompletionKit
  class ProviderCredential < ApplicationRecord
    PROVIDERS = %w[openai anthropic llama].freeze

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
