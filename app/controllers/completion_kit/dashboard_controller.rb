module CompletionKit
  class DashboardController < ApplicationController
    def show
      return redirect_to(onboarding_path) unless workspace_ready?

      @prompt_count = Prompt.current_versions.count
      @run_count = Run.display_scoped.count
      @dataset_count = Dataset.count
      @metric_count = Metric.count
      @recent_runs = Run.display_scoped.order(created_at: :desc).limit(5)

      # Serving is independent of evaluating: a workspace that only fetches
      # prompts over the API and never runs an eval is exactly the audience for
      # this, so it sits outside the run-count gate below.
      @top_served = DashboardStats.top_served(since: 7.days.ago)
      @serve_activity = DashboardStats.serve_activity

      return unless Run.count > 5

      @activity = DashboardStats.activity
      @worst_metric = DashboardStats.worst_metric(since: 7.days.ago)
      @failures = DashboardStats.failures(since: 7.days.ago)
      @failing_checks = DashboardStats.failing_checks(since: 7.days.ago)
      @ignored_metrics = DashboardDismissal.metrics
      @ignored_failures = DashboardDismissal.failures
      @prompt_changes = DashboardStats.prompt_changes
    end
  end
end
