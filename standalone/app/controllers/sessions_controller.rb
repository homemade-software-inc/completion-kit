class SessionsController < ActionController::Base
  layout "login"
  helper CompletionKit::ApplicationHelper

  def new
    redirect_to root_path if session[:authenticated]
  end

  def create
    cfg = CompletionKit.config
    if cfg.username && cfg.password &&
        ActiveSupport::SecurityUtils.secure_compare(params[:username].to_s, cfg.username) &
        ActiveSupport::SecurityUtils.secure_compare(params[:password].to_s, cfg.password)
      session[:authenticated] = true
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid username or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path
  end
end
