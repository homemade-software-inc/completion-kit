require "faraday"

module CompletionKit
  class GenerateRowJob < ApplicationJob
    queue_as :llm

    limits_concurrency to: ENV.fetch("COMPLETION_KIT_PER_RUN_CONCURRENCY", 5).to_i,
                       key: ->(run_id, _) { "run:#{run_id}" },
                       duration: 10.minutes

    def self.rate_limit_wait(executions)
      30 * executions
    end

    retry_on Faraday::TimeoutError,
             Faraday::ConnectionFailed,
             wait: :polynomially_longer, attempts: 5

    retry_on CompletionKit::RateLimitError,
             wait: method(:rate_limit_wait), attempts: 5

    discard_on ActiveJob::DeserializationError
    discard_on CompletionKit::ConfigurationError

    rescue_from(StandardError) do |error|
      Rails.error.report(error, handled: true, context: { job: self.class.name, run_id: @run_id, response_id: @response_id })
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    before_perform do |job|
      response = Response.find_by(id: job.arguments.last)
      next unless response
      response.update!(status: "retrying", attempts: response.attempts + 1)
    end

    def perform(run_id, response_id)
      @run_id = run_id
      @response_id = response_id

      response = Response.find(response_id)
      run = response.run
      prompt = run.prompt

      row = parsed_input(response)
      rendered = CsvProcessor.apply_variables(prompt, row)
      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

      raise ConfigurationError, client.configuration_errors.join(", ") unless client.configured?

      text = client.generate_completion(rendered, model: prompt.llm_model, temperature: run.temperature)
      raise StandardError, text.to_s.sub(/\AError:\s*/, "") if text.to_s.start_with?("Error:")

      if client.respond_to?(:temperature_dropped?) && client.temperature_dropped? && !run.temperature_ignored?
        run.update_columns(temperature_ignored: true)
      end

      response.update!(
        status: "succeeded",
        response_text: text,
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )

      if run.judge_configured?
        run.metrics.each do |metric|
          JudgeReviewJob.perform_later(response.id, metric.id, run.id)
        end
      end

      enqueue_completion_check
    end

    private

    def parsed_input(response)
      return {} if response.input_data.blank?
      JSON.parse(response.input_data)
    rescue JSON::ParserError
      {}
    end

    def record_terminal_failure!(error)
      response = Response.find_by(id: @response_id)
      return unless response

      response.update!(
        status: "failed",
        error_provider: provider_for(response),
        error_class: error.class.name,
        error_status: error.respond_to?(:status) ? error.status : nil,
        error_message: error.message.to_s.truncate(2000)
      )
    end

    def provider_for(response)
      response.run&.prompt&.llm_model_provider
    end

    def enqueue_completion_check
      RunCompletionCheckJob.perform_later(@run_id)
    end
  end
end
