require "bundler/setup"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--default-path spec"
end

task default: :spec
