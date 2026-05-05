module CompletionKit
  class JudgeReviewJob < ApplicationJob
    queue_as :llm

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
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    before_perform do |job|
      response_id, metric_id = job.arguments
      response = Response.find_by(id: response_id)
      next unless response
      review = response.reviews.find_or_initialize_by(metric_id: metric_id)
      review.metric_name ||= Metric.find_by(id: metric_id)&.name || "(deleted metric)"
      review.attempts = (review.attempts || 0) + 1
      review.status = "retrying"
      review.save!(validate: false)
      response.run.send(:broadcast_response_update, response) if response.run
    end

    def perform(response_id, metric_id)
      @response_id = response_id
      @metric_id = metric_id

      response = Response.find(response_id)
      metric = Metric.find(metric_id)
      run = response.run

      config = ApiConfig.for_model(run.judge_model).merge(judge_model: run.judge_model)
      judge = JudgeService.new(config)

      evaluation = judge.evaluate(
        response.response_text,
        response.expected_output,
        run.prompt.template,
        criteria: metric.instruction.to_s,
        rubric_text: metric.display_rubric_text,
        input_data: response.input_data
      )

      review = response.reviews.find_or_initialize_by(metric_id: metric.id)
      review.assign_attributes(
        metric_name: metric.name,
        instruction: metric.instruction.to_s,
        status: "succeeded",
        ai_score: evaluation[:score],
        ai_feedback: evaluation[:feedback],
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )
      review.save!

      run.send(:broadcast_response_update, response)
      enqueue_completion_check
    end

    private

    def record_terminal_failure!(error)
      response_id = @response_id || arguments.first
      metric_id = @metric_id || arguments.last
      response = Response.find_by(id: response_id)
      return unless response

      review = response.reviews.find_or_initialize_by(metric_id: metric_id)
      review.assign_attributes(
        metric_name: review.metric_name || Metric.find_by(id: metric_id)&.name || "(deleted metric)",
        status: "failed",
        error_provider: provider_for(response),
        error_class: error.class.name,
        error_status: error.respond_to?(:status) ? error.status : nil,
        error_message: error.message.to_s.truncate(2000)
      )
      review.save!(validate: false)
      response.run&.send(:broadcast_response_update, response)
    end

    def provider_for(response)
      run = response.run
      return nil unless run&.judge_model
      ApiConfig.provider_for_model(run.judge_model)
    end

    def enqueue_completion_check
      response_id = @response_id || arguments.first
      response = Response.find_by(id: response_id)
      RunCompletionCheckJob.perform_later(response.run_id) if response
    end
  end
end
