module CompletionKit
  module MetricSelection
    extend ActiveSupport::Concern

    included do
      validate :selected_metrics_in_scope, if: -> { @metric_selection_assigned }
      after_save :attach_selected_metrics, if: -> { @metric_selection_assigned }
    end

    def selected_metric_ids=(ids)
      @metric_selection_assigned = !ids.nil?
      @selected_metric_ids = ids
    end

    def selected_metric_ids
      @metric_selection_assigned ? normalize_metric_ids(@selected_metric_ids) : metric_ids
    end

    private

    def normalize_metric_ids(ids)
      Array(ids).reject(&:blank?).map(&:to_i).uniq
    end

    def selected_metrics_in_scope
      wanted = selected_metric_ids
      errors.add(:metric_ids, "include one that isn't available") if CompletionKit::Metric.where(id: wanted).count < wanted.size
    end

    def attach_selected_metrics
      replace_metrics!(@selected_metric_ids)
      @metric_selection_assigned = false
    end
  end
end
