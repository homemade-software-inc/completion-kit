require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
  minimum_coverage line: 100, branch: 100

  track_files "{app,lib,config}/**/*.rb"

  skip "/spec/"
  skip "/db/"
  skip "/vendor/"
  skip "/gems/"
  skip "/pkg/"
  skip "/app/assets/"
  skip "/app/views/"
  skip "/lib/tasks/"
  skip "/lib/generators/completion_kit/templates/"
  skip "/lib/completion_kit/engine.rb"

  group "Controllers", "app/controllers"
  group "Models", "app/models"
  group "Services", "app/services"
  group "Engine", "lib/completion_kit"
  group "Generators", "lib/generators"
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
