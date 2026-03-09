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

    def create_eval_directory
      empty_directory "evals/fixtures"
      create_file "evals/example_eval.rb", <<~RUBY
        CompletionKit.define_eval("example") do |e|
          e.prompt "your_prompt_name"
          e.dataset "evals/fixtures/example.csv"
          e.judge_model "gpt-4.1"

          e.metric :relevance, threshold: 7.0
        end
      RUBY
    end
    
    def show_readme
      readme 'README'
    end
  end
end
