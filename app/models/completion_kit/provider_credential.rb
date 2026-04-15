module CompletionKit
  class ProviderCredential < ApplicationRecord
    include Turbo::Broadcastable
    PROVIDERS = %w[openai anthropic llama openrouter].freeze
    PROVIDER_LABELS = {
      "openai" => "OpenAI",
      "anthropic" => "Anthropic",
      "llama" => "Llama / Ollama / Custom endpoint",
      "openrouter" => "OpenRouter"
    }.freeze

    encrypts :api_key

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

    def prompt_count
      model_ids = Model.where(provider: provider).pluck(:model_id)
      return 0 if model_ids.empty?
      Prompt.where(llm_model: model_ids, current: true).count
    end

    def judge_count
      model_ids = Model.where(provider: provider).pluck(:model_id)
      return 0 if model_ids.empty?
      Run.where(judge_model: model_ids).count
    end

    def last_used_at
      model_ids = Model.where(provider: provider).pluck(:model_id)
      return nil if model_ids.empty?
      prompt_ids = Prompt.where(llm_model: model_ids).pluck(:id)
      Run.where("prompt_id IN (?) OR judge_model IN (?)", prompt_ids, model_ids)
         .where.not(status: "pending")
         .maximum(:created_at)
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
      broadcast_model_dropdowns
    end

    private

    def enqueue_discovery
      update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      ModelDiscoveryJob.perform_later(id)
    end

    def broadcast_model_dropdowns
      helper = ApplicationController.helpers
      gen_html = helper.ck_model_options_html(:generation)
      judge_html = '<option value="">None</option>' + helper.ck_model_options_html(:judging)

      Turbo::StreamsChannel.broadcast_action_to(
        "completion_kit_provider_#{id}",
        action: :replace,
        target: "prompt_llm_model",
        html: "<select name=\"prompt[llm_model]\" id=\"prompt_llm_model\" class=\"ck-input\">#{gen_html}</select>"
      )
      Turbo::StreamsChannel.broadcast_action_to(
        "completion_kit_provider_#{id}",
        action: :replace,
        target: "run_judge_model",
        html: "<select name=\"run[judge_model]\" id=\"run_judge_model\" class=\"ck-input\">#{judge_html}</select>"
      )
    end

    def render_partial(partial, locals)
      CompletionKit::ApplicationController.render(partial: partial, locals: locals)
    end
  end
end
