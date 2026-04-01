module CompletionKit
  class ProviderCredential < ApplicationRecord
    include Turbo::Broadcastable
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

    after_save :enqueue_discovery

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

    def model_pattern
      case provider
      when "openai" then /\Agpt-/
      when "anthropic" then /\Aclaude-/
      when "llama" then /llama/i
      end
    end

    def prompt_count
      pattern = model_pattern
      return 0 unless pattern
      Prompt.all.count { |p| p.llm_model&.match?(pattern) }
    end

    def judge_count
      pattern = model_pattern
      return 0 unless pattern
      Run.where.not(judge_model: [nil, ""]).all.count { |r| r.judge_model.match?(pattern) }
    end

    def last_used_at
      pattern = model_pattern
      return nil unless pattern
      runs = Run.where.not(status: "pending").order(created_at: :desc)
      run = runs.find { |r| r.prompt.llm_model&.match?(pattern) || r.judge_model&.match?(pattern) }
      run&.created_at
    end

    def broadcast_discovery_progress
      broadcast_replace_to(
        "completion_kit_provider_#{id}",
        target: "discovery_status_#{id}",
        html: render_partial("completion_kit/provider_credentials/discovery_status", provider_credential: self)
      )
    end

    def broadcast_discovery_complete
      broadcast_discovery_progress
    end

    private

    def enqueue_discovery
      update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      ModelDiscoveryJob.perform_later(id)
    end

    def render_partial(partial, locals)
      CompletionKit::ApplicationController.render(partial: partial, locals: locals)
    end
  end
end
