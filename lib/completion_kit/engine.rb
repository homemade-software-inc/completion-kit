module CompletionKit
  class Engine < ::Rails::Engine
    isolate_namespace CompletionKit
    
    initializer "completion_kit.assets" do |app|
      app.config.assets.precompile += %w( completion_kit/application.css )
    end
    
    initializer "completion_kit.autoload", before: :set_autoload_paths do |app|
      app.config.autoload_paths += %W(
        #{root}/app/services
        #{root}/app/models/concerns
      )
    end
    
    config.to_prepare do
      # Load extensions
      Dir.glob(CompletionKit::Engine.root.join("app", "models", "completion_kit", "concerns", "**", "*.rb")).each do |c|
        require_dependency(c)
      end
      
      # Load services
      Dir.glob(CompletionKit::Engine.root.join("app", "services", "completion_kit", "**", "*.rb")).each do |s|
        require_dependency(s)
      end
    end
    
    initializer "completion_kit.routes" do |app|
      # Mount routes
      app.routes.append do
        mount CompletionKit::Engine => "/completion_kit"
      end
    end
    
    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: 'spec/factories'
    end
  end
end
