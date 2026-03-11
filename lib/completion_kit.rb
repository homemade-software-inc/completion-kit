require "completion_kit/version"
require "completion_kit/engine"
require "completion_kit/eval_definition"
require "completion_kit/eval_runner"
require "completion_kit/eval_formatter"

module CompletionKit
  # Configuration for the CompletionKit module
  class Configuration
    attr_accessor :openai_api_key, :anthropic_api_key, :llama_api_key, :llama_api_endpoint
    attr_accessor :judge_model, :high_quality_threshold, :medium_quality_threshold
    
    def initialize
      # API keys
      @openai_api_key = ENV['OPENAI_API_KEY']
      @anthropic_api_key = ENV['ANTHROPIC_API_KEY']
      @llama_api_key = ENV['LLAMA_API_KEY']
      @llama_api_endpoint = ENV['LLAMA_API_ENDPOINT']
      
      # Judge configuration
      @judge_model = "gpt-4.1"
      @high_quality_threshold = 4
      @medium_quality_threshold = 3
    end
  end
  
  # Access to the configuration
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
        generation_model: prompt.llm_model,
        assessment_model: prompt.assessment_model,
        review_guidance: prompt.effective_review_guidance,
        metric_group: prompt.metric_group&.name,
        metrics: prompt.assessment_metrics.map do |metric|
          {
            name: metric.name,
            criteria: metric.respond_to?(:criteria) ? metric.criteria : nil,
            evaluation_steps: metric.respond_to?(:evaluation_steps) ? metric.evaluation_steps : [],
            rubric_text: metric.respond_to?(:display_rubric_text) ? metric.display_rubric_text : metric.rubric_text,
            rubric_bands: metric.respond_to?(:rubric_bands_for_form) ? metric.rubric_bands_for_form : metric.rubric_bands
          }
        end
      }
    end

    def render_current_prompt(identifier, variables = {})
      prompt = current_prompt(identifier)
      CsvProcessor.apply_variables(prompt, variables.stringify_keys)
    end

    def registered_evals
      @registered_evals ||= []
    end

    def define_eval(name, &block)
      defn = EvalDefinition.new(name)
      block.call(defn)
      registered_evals << defn
    end

    def clear_evals!
      @registered_evals = []
    end
  end
end
