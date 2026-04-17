require_relative "lib/completion_kit/version"

Gem::Specification.new do |spec|
  spec.name        = "completion-kit"
  spec.version     = CompletionKit::VERSION
  spec.authors     = ["Damien Bastin"]
  spec.email       = ["damien@homemade.software"]
  spec.homepage    = "https://github.com/homemade-software-inc/completion-kit"
  spec.summary     = "Your prompts need tests too. Run them against real data, score outputs with an LLM judge, iterate until they work."
  spec.description = "CompletionKit is a prompt testing platform that runs as a Rails engine or a standalone app. Run prompts against real datasets, score every output with an LLM judge against criteria you define, track prompt versions, and get AI-generated improvement suggestions grounded in your actual results. Includes a web UI, REST API, and a built-in MCP server with 36 tools."
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
