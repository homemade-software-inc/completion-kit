module CompletionKit
  class ApplicationController < ActionController::Base
    layout "completion_kit/application"

    before_action :authenticate_completion_kit!

    private

    def authenticate_completion_kit!
      cfg = CompletionKit.config

      if (cfg.username && !cfg.password) || (cfg.password && !cfg.username)
        raise CompletionKit::ConfigurationError,
          "Both username and password are required for built-in auth."
      end

      if cfg.auth_strategy
        cfg.auth_strategy.call(self)
      elsif cfg.username && cfg.password
        authenticate_or_request_with_http_basic("CompletionKit") do |u, p|
          ActiveSupport::SecurityUtils.secure_compare(u, cfg.username) &
            ActiveSupport::SecurityUtils.secure_compare(p, cfg.password)
        end
      elsif Rails.env.production?
        render plain: "CompletionKit authentication not configured. See README for setup instructions.",
               status: :forbidden
      end
    end
  end
end
