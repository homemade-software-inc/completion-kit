module CompletionKit
  class CheckReviewJob < ApplicationJob
    queue_as :default

    rescue_from(StandardError) do |error|
      Rails.error.report(error, handled: true, context: { job: self.class.name, run_id: @run_id, response_id: @response_id, metric_id: @metric_id })
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    def perform(response_id, metric_id, run_id = nil)
      @response_id = response_id
      @metric_id = metric_id
      @run_id = run_id

      response = Response.find(response_id)
      metric = Metric.find(metric_id)
      result = evaluate(response, metric.check_config || {})

      review = response.reviews.find_or_initialize_by(metric_id: metric.id)
      current_metric_version = MetricVersion.ensure_current_for(metric)
      review.assign_attributes(
        metric_name: metric.name,
        metric_version_id: current_metric_version.id,
        status: "succeeded",
        passed: result.passed,
        ai_score: nil,
        check_score: result.score,
        ai_feedback: result.detail,
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )
      review.save!

      enqueue_completion_check
    end

    private

    def evaluate(response, config)
      kind = config["check_kind"]
      target_value = resolve_target(response, config, kind)
      if target_value.equal?(Checks::TargetResolver::UNRESOLVED)
        return ungraded(kind, "could not resolve target")
      end

      if config["compare_to"] == "expected" && Checks::Registry.compares_value?(kind)
        expected_value = resolve_expected(response, config, kind)
        if expected_value.equal?(Checks::ExpectedResolver::UNRESOLVED)
          return ungraded(kind, "no expected value for this row")
        end
        config = config.merge(Checks::Registry.expected_key(kind) => expected_value)
      end

      Checks::Registry.fetch(kind).call(target_value, config)
    end

    def ungraded(kind, detail)
      Checks::Result.new(passed: false, detail: detail, score: Checks::Registry.scores?(kind) ? 0.0 : nil)
    end

    def resolve_target(response, config, kind)
      if Checks::Registry.raw_target?(kind)
        Checks::TargetResolver.call_value(response, config)
      else
        Checks::TargetResolver.call(response, config)
      end
    end

    def resolve_expected(response, config, kind)
      if Checks::Registry.raw_expected?(kind)
        Checks::ExpectedResolver.call_value(response, config)
      else
        Checks::ExpectedResolver.call(response, config)
      end
    end

    def record_terminal_failure!(error)
      response = Response.find_by(id: @response_id)
      return unless response

      review = response.reviews.find_or_initialize_by(metric_id: @metric_id)
      review.assign_attributes(
        metric_name: review.metric_name || Metric.find_by(id: @metric_id)&.name || "(deleted metric)",
        status: "failed",
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(2000)
      )
      review.save!(validate: false)
    end

    def enqueue_completion_check
      response = Response.find_by(id: @response_id)
      RunCompletionCheckJob.perform_later(response.run_id) if response
    end
  end
end
