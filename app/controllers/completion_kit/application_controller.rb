module CompletionKit
  class ApplicationController < ActionController::Base
    helper Heroicons::IconsHelper
    layout "completion_kit/application"

    ONBOARDING_DISMISS_COOKIE = :ck_onboarding_dismissed

    rate_limit to: CompletionKit.config.web_rate_limit, within: 1.minute,
               with: -> { render plain: "Rate limit exceeded. Please slow down.", status: :too_many_requests }
    before_action :authenticate_completion_kit!

    private

    def workspace_ready?
      CompletionKit::Onboarding::Checklist.new.complete? ||
        cookies[ONBOARDING_DISMISS_COOKIE].present?
    end

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
      elsif !Rails.env.local?
        render plain: "CompletionKit authentication not configured. See README for setup instructions.",
               status: :forbidden
      end
    end
  end
end
