class HomeController < ActionController::Base
  before_action :authenticate!

  def index
    redirect_to completion_kit.dashboard_path
  end

  private

  def authenticate!
    cfg = CompletionKit.config
    return unless cfg.username && cfg.password
    return if session[:authenticated]

    redirect_to login_path
  end
end
