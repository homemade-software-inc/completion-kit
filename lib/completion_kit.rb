require "completion_kit/errors"
require "completion_kit/version"
require "completion_kit/engine"
require "completion_kit/concurrency_check"

module CompletionKit
  class Configuration
    attr_accessor :openai_api_key, :anthropic_api_key, :ollama_api_key, :ollama_api_endpoint
    attr_accessor :judge_model, :high_quality_threshold, :medium_quality_threshold
    attr_accessor :username, :password, :auth_strategy, :api_token
    attr_accessor :tenant_scope, :tenant_scope_columns
    attr_accessor :api_reference_authentication_partial
    attr_accessor :runs_display_scope, :runs_display_footer_partial
    attr_accessor :api_rate_limit, :web_rate_limit, :max_upload_bytes
    attr_accessor :allow_loopback_endpoints
    attr_accessor :judge_agreement_enabled
    attr_accessor :judge_examples_from_reviews
    attr_accessor :on_run_created
    attr_accessor :on_run_started

    def initialize
      @openai_api_key = ENV['OPENAI_API_KEY']
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY']
      @ollama_api_key = ENV['OLLAMA_API_KEY']
      @ollama_api_endpoint = ENV['OLLAMA_API_ENDPOINT']

      @judge_model = nil
      @high_quality_threshold = 4
      @medium_quality_threshold = 3

      @api_rate_limit = 120
      @web_rate_limit = 300
      @max_upload_bytes = 25 * 1024 * 1024

      @allow_loopback_endpoints = true
      @judge_agreement_enabled = true
      @judge_examples_from_reviews = false

      @api_reference_authentication_partial = "completion_kit/api_reference/authentication"
    end

    def tenant_scope_columns
      @tenant_scope_columns ||= []
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield(config) if block_given?
    end

    def current_prompt(identifier)
      Prompt.current_for(identifier)
    end

    def current_prompt_payload(identifier)
      prompt = current_prompt(identifier)

      {
        name: prompt.name,
        family_key: prompt.family_key,
        version_number: prompt.version_number,
        template: prompt.template,
        generation_model: prompt.llm_model
      }
    end

    def render_current_prompt(identifier, variables = {})
      prompt = current_prompt(identifier)
      CsvProcessor.apply_variables(prompt, variables.stringify_keys)
    end

  end
end
