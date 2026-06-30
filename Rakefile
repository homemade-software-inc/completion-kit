require "bundler/setup"
require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = "--default-path spec"
end

task default: :spec

desc "Run the full suite with judge API keys cleared, matching CI's keyless environment"
task :release_guard do
  sh "OPENAI_API_KEY= ANTHROPIC_API_KEY= OLLAMA_API_KEY= bundle exec rspec"
end

Rake::Task["release:guard_clean"].enhance([:release_guard])
