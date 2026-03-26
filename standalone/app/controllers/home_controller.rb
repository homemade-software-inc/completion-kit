class HomeController < ActionController::Base
  layout "application"

  def index
    @has_data = CompletionKit::Prompt.any?
    if @has_data
      @prompt_count = CompletionKit::Prompt.current_versions.count
      @run_count = CompletionKit::Run.count
      @recent_runs = CompletionKit::Run.order(created_at: :desc).limit(5)
    end
  end
end
