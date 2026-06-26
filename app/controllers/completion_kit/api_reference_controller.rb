module CompletionKit
  class ApiReferenceController < ApplicationController
    def index
      @published_prompts = Prompt.current_versions.order(name: :asc)
      @recent_runs = Run.includes(:prompt).display_scoped.order(created_at: :desc).limit(10)
      @datasets = Dataset.order(name: :asc)
      @metrics = Metric.order(name: :asc)
      @metric_groups = MetricGroup.includes(:metrics).order(name: :asc)
      @tags = Tag.order(name: :asc)
      @provider_credentials = ProviderCredential.order(:provider)
      @token = CompletionKit.config.api_token
      @base_url = request.base_url + request.script_name
    end
  end
end
