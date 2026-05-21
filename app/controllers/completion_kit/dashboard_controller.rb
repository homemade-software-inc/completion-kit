module CompletionKit
  class DashboardController < ApplicationController
    def show
      return redirect_to(onboarding_path) unless workspace_ready?

      @prompt_count = Prompt.current_versions.count
      @run_count = Run.count
      @dataset_count = Dataset.count
      @metric_count = Metric.count
      @recent_runs = Run.order(created_at: :desc).limit(5)

      return unless @run_count > 5

      @activity = DashboardStats.activity
      @worst_metric = DashboardStats.worst_metric(since: 7.days.ago)
      @failures = DashboardStats.failures(since: 7.days.ago)
      @ignored_metrics = DashboardDismissal.metrics
      @ignored_failures = DashboardDismissal.failures
      @prompt_changes = DashboardStats.prompt_changes
    end
  end
end
