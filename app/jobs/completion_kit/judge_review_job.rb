require "faraday"

module CompletionKit
  class JudgeReviewJob < ApplicationJob
    queue_as :llm

    limits_concurrency to: ENV.fetch("COMPLETION_KIT_PER_RUN_CONCURRENCY", 5).to_i,
                       key: ->(response_id, _metric_id, run_id = nil) {
                         "run:#{run_id || Response.where(id: response_id).pick(:run_id)}"
                       },
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
      Rails.error.report(error, handled: true, context: { job: self.class.name, run_id: @run_id, review_id: @review_id })
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    before_perform do |job|
      response_id, metric_id, _run_id = job.arguments
      response = Response.find_by(id: response_id)
      next unless response
      review = response.reviews.find_or_initialize_by(metric_id: metric_id)
      review.metric_name ||= Metric.find_by(id: metric_id)&.name || "(deleted metric)"
      review.attempts = (review.attempts || 0) + 1
      review.status = "retrying"
      review.save!(validate: false)
    end

    def perform(response_id, metric_id, _run_id = nil)
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
        run.prompt&.template,
        criteria: metric.instruction.to_s,
        rubric_text: metric.display_rubric_text,
        input_data: response.input_data
      )

      review = response.reviews.find_or_initialize_by(metric_id: metric.id)
      current_metric_version = MetricVersion.ensure_current_for(metric)
      review.assign_attributes(
        metric_name: metric.name,
        instruction: metric.instruction.to_s,
        metric_version_id: current_metric_version.id,
        status: "succeeded",
        ai_score: evaluation[:score],
        ai_feedback: evaluation[:feedback],
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )
      review.save!

      confirm_judging_capability(run.judge_model)
      enqueue_completion_check
    end

    private

    # A model with supports_judging == nil ("untested") just produced a valid
    # review — promote it to confirmed. No-op once confirmed (so repeated runs
    # don't churn the row), and a model already flagged as a bad judge stays so.
    def confirm_judging_capability(judge_model_id)
      model = Model.find_by(provider: ApiConfig.provider_for_model(judge_model_id), model_id: judge_model_id)
      return unless model && model.supports_judging.nil?
      model.update_columns(supports_judging: true, judging_error: nil)
    end

    def record_terminal_failure!(error)
      response = Response.find_by(id: @response_id)
      return unless response

      review = response.reviews.find_or_initialize_by(metric_id: @metric_id)
      review.assign_attributes(
        metric_name: review.metric_name || Metric.find_by(id: @metric_id)&.name || "(deleted metric)",
        status: "failed",
        error_provider: provider_for(response),
        error_class: error.class.name,
        error_status: error.respond_to?(:status) ? error.status : nil,
        error_message: error.message.to_s.truncate(2000)
      )
      review.save!(validate: false)
    end

    def provider_for(response)
      run = response.run
      return nil unless run.judge_model
      ApiConfig.provider_for_model(run.judge_model)
    end

    def enqueue_completion_check
      response = Response.find_by(id: @response_id)
      RunCompletionCheckJob.perform_later(response.run_id) if response
    end
  end
end
