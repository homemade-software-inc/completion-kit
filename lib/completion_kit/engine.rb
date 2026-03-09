module CompletionKit
  class Engine < ::Rails::Engine
    isolate_namespace CompletionKit

    paths.add "app/services", eager_load: true

    def self.register_assets(app)
      app.config.assets.precompile += %w( completion_kit/application.css )
    end

    initializer("completion_kit.assets") { |app| Engine.register_assets(app) }

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end
  end
end
