require "turbo-rails"
require "heroicons-rails"

module CompletionKit
  class Engine < ::Rails::Engine
    isolate_namespace CompletionKit

    paths.add "app/services", eager_load: true

    ROUTES_WARMUP_LOCK = Mutex.new
    @routes_warmed = false

    # Materialise the engine's lazy route set once, single-threaded. Background
    # worker threads that render engine partials for Turbo broadcasts otherwise
    # race the lazy first-load and raise "undefined method 'run_response_path'"
    # (production survives only because eager_load finalises routes at boot).
    def self.warm_routes!
      ROUTES_WARMUP_LOCK.synchronize do
        return if @routes_warmed
        routes.url_helpers.root_path
        @routes_warmed = true
      rescue ActionController::UrlGenerationError
        @routes_warmed = true
      end
    end

    def self.register_assets(app)
      app.config.assets.precompile += %w(
        completion_kit/application.css
        completion_kit/application.js
        completion_kit/logo.png
        completion_kit/favicon.ico
      )
    end

    initializer("completion_kit.assets") { |app| Engine.register_assets(app) }

    config.after_initialize do
      cfg = CompletionKit.config
      unless cfg.username || cfg.auth_strategy
        Rails.logger.warn "[CompletionKit] WARNING: No authentication configured. All routes are publicly accessible."
      end
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end
  end
end
