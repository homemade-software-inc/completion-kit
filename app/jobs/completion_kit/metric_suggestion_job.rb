module CompletionKit
  class MetricSuggestionJob < ApplicationJob
    queue_as :llm

    def perform(metric_id)
      metric = Metric.find_by(id: metric_id)
      return unless metric

      MetricVersion.drafts.where(metric_id: metric.id, source: "suggestion").destroy_all

      variants = MetricVariantGenerator.new(metric, count: 1).call
      if variants.empty?
        broadcast_status(metric, partial: "completion_kit/metrics/suggestion_failed", locals: { metric: metric })
        return
      end

      draft = MetricVariantGenerator.new(metric).persist!(variants).max_by(&:version_number)
      summary = MetricImprovementValidator.new(metric, draft).call
      draft.update!(validation_summary: summary)

      broadcast_status(metric, partial: "completion_kit/metrics/suggestion_ready", locals: { metric: metric, draft: draft })
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
