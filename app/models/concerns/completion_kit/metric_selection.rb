module CompletionKit
  module MetricSelection
    extend ActiveSupport::Concern

    included do
      after_save :attach_selected_metrics, if: -> { @metric_selection_assigned }
    end

    def selected_metric_ids=(ids)
      @metric_selection_assigned = !ids.nil?
      @selected_metric_ids = ids
    end

    private

    def selected_metrics_out_of_scope?
      return false unless @metric_selection_assigned

      wanted = Array(@selected_metric_ids).reject(&:blank?).map(&:to_s).uniq
      CompletionKit::Metric.where(id: wanted).count < wanted.size
    end

    def attach_selected_metrics
      @metric_selection_assigned = false
      replace_metrics!(@selected_metric_ids)
    end
  end
end
