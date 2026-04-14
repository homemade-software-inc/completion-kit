require_relative "lib/completion_kit/version"

Gem::Specification.new do |spec|
  spec.name        = "completion-kit"
  spec.version     = CompletionKit::VERSION
  spec.authors     = ["Damien Bastin"]
  spec.email       = ["damien@homemade.software"]
  spec.homepage    = "https://github.com/homemade-software-inc/completion-kit"
  spec.summary     = "Rails engine for testing, scoring, and improving GenAI prompts against real data — with a web UI, REST API, and built-in MCP server."
  spec.description = "CompletionKit is a mountable Rails engine for rigorous prompt testing: run prompts against datasets, score outputs with an LLM-as-judge against custom metrics and rubrics, track versions, and iterate with AI-assisted improvement suggestions. Every resource is accessible through a bearer-token REST API and a built-in Model Context Protocol server, so you can drive it from a browser, from HTTP clients, or directly from agents like Claude Code."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/homemade-software-inc/completion-kit"
  spec.metadata["changelog_uri"] = "https://github.com/homemade-software-inc/completion-kit/blob/main/CHANGELOG.md"

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
  spec.add_dependency "turbo-rails", ">= 1.5"
  spec.add_dependency "heroicons-rails", "~> 1.2"
  spec.add_development_dependency "sqlite3", "~> 2.9"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.2"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
