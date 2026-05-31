require "faraday"

module CompletionKit
  class MetricSuggestionJob < ApplicationJob
    queue_as :llm

    retry_on Faraday::TimeoutError, Faraday::ConnectionFailed, wait: :polynomially_longer, attempts: 5
    retry_on CompletionKit::RateLimitError, wait: :polynomially_longer, attempts: 5

    rescue_from(StandardError) do |error|
      Rails.error.report(error, handled: true, context: { job: self.class.name })
      broadcast_status(@metric, partial: "completion_kit/metrics/suggestion_failed", locals: { metric: @metric })
    end

    def perform(metric_id)
      @metric = Metric.find_by(id: metric_id)
      return unless @metric

      MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").destroy_all

      generator = MetricVariantGenerator.new(@metric, count: 1)
      variants = generator.call
      if variants.empty?
        broadcast_status(@metric, partial: "completion_kit/metrics/suggestion_failed", locals: { metric: @metric })
        return
      end

      draft = generator.persist!(variants).max_by(&:version_number)
      summary = MetricImprovementValidator.new(@metric, draft).call
      draft.update!(validation_summary: summary)

      broadcast_status(@metric, partial: "completion_kit/metrics/suggestion_ready", locals: { metric: @metric, draft: draft })
    end

    private

    def broadcast_status(metric, partial:, locals:)
      html = CompletionKit::ApplicationController.render(partial: partial, locals: locals)
      Turbo::StreamsChannel.broadcast_replace_to(
        "metric_#{metric.id}_suggestion",
        target: "ck-suggestion-status-#{metric.id}",
        html: html
      )
    end
  end
end
