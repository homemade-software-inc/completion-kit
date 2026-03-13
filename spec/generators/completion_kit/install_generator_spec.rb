require "rails_helper"
require "rails/generators"
require "generators/completion_kit/install_generator"

RSpec.describe CompletionKit::InstallGenerator do
  it "defines the expected source root" do
    expect(described_class.source_root).to end_with("/lib/generators/completion_kit/templates")
  end

  it "invokes template, route, rake, and readme helpers with the expected arguments" do
    generator = described_class.new

    allow(generator).to receive(:template)
    allow(generator).to receive(:route)
    allow(generator).to receive(:rake)
    allow(generator).to receive(:readme)
    allow(generator).to receive(:empty_directory)
    allow(generator).to receive(:create_file)

    generator.create_initializer
    generator.mount_engine
    generator.copy_migrations
    generator.show_readme
    generator.create_eval_directory

    expect(generator).to have_received(:template).with("initializer.rb", "config/initializers/completion_kit.rb")
    expect(generator).to have_received(:route).with("mount CompletionKit::Engine => '/completion_kit'").once
    expect(generator).to have_received(:rake).with("completion_kit:install:migrations")
    expect(generator).to have_received(:readme).with("README")
    expect(generator).to have_received(:empty_directory).with("evals/fixtures")
    expect(generator).to have_received(:create_file).with("evals/example_eval.rb", anything)
  end
end
