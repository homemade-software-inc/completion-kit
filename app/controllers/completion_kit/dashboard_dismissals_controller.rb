module CompletionKit
  class DashboardDismissalsController < ApplicationController
    WINDOW = 7.days

    def create
      record = resolve_dismissable
      DashboardDismissal.create(dismissable: record, baseline_score: baseline_for(record))
      render_cards
    end

    def destroy
      DashboardDismissal.find(params[:id]).destroy
      render_cards
    end

    private

    def dismissal_params
      params.require(:dashboard_dismissal).permit(:dismissable_type, :dismissable_id)
    end

    def resolve_dismissable
      type = dismissal_params[:dismissable_type]
      raise ActiveRecord::RecordNotFound unless DashboardDismissal::DISMISSABLE_TYPES.include?(type)
      type.constantize.find(dismissal_params[:dismissable_id])
    end

    def baseline_for(record)
      return nil unless record.is_a?(Metric)
      return DashboardStats.metric_pass_rate(record.id, since: WINDOW.ago) if record.check?
      DashboardStats.metric_average(record.id, since: WINDOW.ago)
    end

    def render_cards
      @worst_metric = DashboardStats.worst_metric(since: WINDOW.ago)
      @failures = DashboardStats.failures(since: WINDOW.ago)
      @ignored_metrics = DashboardDismissal.metrics
      @ignored_failures = DashboardDismissal.failures
      render :refresh, formats: [:turbo_stream]
    end
  end
end
