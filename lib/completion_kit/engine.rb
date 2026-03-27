require "turbo-rails"
require "heroicons-rails"

module CompletionKit
  class Engine < ::Rails::Engine
    isolate_namespace CompletionKit

    initializer("completion_kit.inflections", before: :load_config_initializers) do
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.irregular "criterion", "criteria"
      end
    end

    paths.add "app/services", eager_load: true

    def self.register_assets(app)
      app.config.assets.precompile += %w( completion_kit/application.css completion_kit/evaluation_steps_controller.js completion_kit/logo-symbol.png )
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
