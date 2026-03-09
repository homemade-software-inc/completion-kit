require "simplecov"

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch
  minimum_coverage line: 100, branch: 100

  track_files "{app,lib,config}/**/*.rb"

  add_filter "/spec/"
  add_filter "/db/"
  add_filter "/vendor/"
  add_filter "/pkg/"
  add_filter "/app/assets/"
  add_filter "/app/views/"
  add_filter "/lib/tasks/"
  add_filter "/lib/generators/completion_kit/templates/"

  add_group "Controllers", "app/controllers"
  add_group "Models", "app/models"
  add_group "Services", "app/services"
  add_group "Engine", "lib/completion_kit"
  add_group "Generators", "lib/generators"
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
