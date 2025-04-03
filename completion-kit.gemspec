require_relative "lib/completion_kit/version"

Gem::Specification.new do |spec|
  spec.name        = "completion-kit"
  spec.version     = CompletionKit::VERSION
  spec.authors     = ["CompletionKit Team"]
  spec.email       = ["info@completionkit.example.com"]
  spec.homepage    = "https://github.com/completionkit/completion-kit"
  spec.summary     = "A GenAI prompt testing platform for Rails applications."
  spec.description = "CompletionKit is a mountable Rails engine that provides a platform for testing GenAI prompts against CSV data, evaluating outputs using LLM judges, and providing quality metrics for each test."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/completionkit/completion-kit"
  spec.metadata["changelog_uri"] = "https://github.com/completionkit/completion-kit/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.0.0", "< 9.0.0"
  spec.add_dependency "csv", "~> 3.2"
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "sassc-rails", "~> 2.1"
  spec.add_dependency "bootstrap", "~> 5.2"
  spec.add_dependency "jquery-rails", "~> 4.5"

  spec.add_development_dependency "sqlite3", "~> 1.6"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.2"
end
