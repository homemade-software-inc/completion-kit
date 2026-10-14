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

    def normalize_metric_ids(ids)
      Array(ids).reject(&:blank?).map(&:to_i).uniq
    end

    def selected_metrics_out_of_scope?
      return false unless @metric_selection_assigned

      wanted = normalize_metric_ids(@selected_metric_ids)
      CompletionKit::Metric.where(id: wanted).count < wanted.size
    end

    def attach_selected_metrics
      @metric_selection_assigned = false
      replace_metrics!(@selected_metric_ids)
    end
  end
end
