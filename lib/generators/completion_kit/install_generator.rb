module CompletionKit
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path('templates', __dir__)
    
    def create_initializer
      template 'initializer.rb', 'config/initializers/completion_kit.rb'
    end
    
    def mount_engine
      route "mount CompletionKit::Engine => '/completion_kit'"
    end
    
    def copy_migrations
      rake 'completion_kit:install:migrations'
    end
    
    def show_readme
      readme 'README'
    end
  end
end
