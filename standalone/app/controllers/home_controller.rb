class HomeController < ActionController::Base
  helper CompletionKit::ApplicationHelper
  layout "application"
  before_action :authenticate!

  def index
    @has_provider = CompletionKit::ProviderCredential.any?
    @has_prompt = CompletionKit::Prompt.any?
    @has_run = CompletionKit::Run.where.not(status: "pending").any?
    @setup_complete = @has_provider && @has_prompt && @has_run
    if @setup_complete
      @prompt_count = CompletionKit::Prompt.current_versions.count
      @run_count = CompletionKit::Run.count
      @recent_runs = CompletionKit::Run.order(created_at: :desc).limit(5)
    end
  end

  private

  def authenticate!
    cfg = CompletionKit.config
    return unless cfg.username && cfg.password
    return if session[:authenticated]

    redirect_to login_path
  end
end
