require "rails_helper"

RSpec.describe "CompletionKit boot smoke" do
  def silently_load(path)
    previous_verbose = $VERBOSE
    $VERBOSE = nil
    load path
  ensure
    $VERBOSE = previous_verbose
  end

  around do |example|
    original_values = {
      openai: CompletionKit.config.openai_api_key,
      anthropic: CompletionKit.config.anthropic_api_key,
      ollama_key: CompletionKit.config.ollama_api_key,
      ollama_endpoint: CompletionKit.config.ollama_api_endpoint,
      judge_model: CompletionKit.config.judge_model
    }

    example.run
  ensure
    CompletionKit.config.openai_api_key = original_values[:openai]
    CompletionKit.config.anthropic_api_key = original_values[:anthropic]
    CompletionKit.config.ollama_api_key = original_values[:ollama_key]
    CompletionKit.config.ollama_api_endpoint = original_values[:ollama_endpoint]
    CompletionKit.config.judge_model = original_values[:judge_model]
  end

  it "supports configuration, versioning, engine boot, and hyphenated require" do
    expect { silently_load(File.expand_path("../../lib/completion_kit/version.rb", __dir__)) }.not_to raise_error
    expect { silently_load(File.expand_path("../../lib/completion_kit/engine.rb", __dir__)) }.not_to raise_error
    expect { silently_load(File.expand_path("../../lib/completion_kit.rb", __dir__)) }.not_to raise_error

    expect(CompletionKit::VERSION).to eq("0.2.1")
    expect(CompletionKit::Engine).to be < Rails::Engine
    expect(CompletionKit::ApplicationController).to be < ActionController::Base
    expect(CompletionKit::ApplicationRecord).to be < ActiveRecord::Base
    expect(CompletionKit::ApplicationJob).to be < ActiveJob::Base
    expect(CompletionKit::ApplicationMailer).to be < ActionMailer::Base
    expect(CompletionKit::ApplicationHelper).to be_a(Module)
    expect(CompletionKit::Engine.initializers.map(&:name)).to include("completion_kit.assets")

    CompletionKit.configure do |config|
      config.openai_api_key = "configured-openai"
      config.anthropic_api_key = "configured-anthropic"
      config.ollama_api_key = "configured-ollama"
      config.ollama_api_endpoint = "https://ollama.example.test"
      config.judge_model = "claude-3-7-sonnet-latest"
    end

    expect(CompletionKit.config.openai_api_key).to eq("configured-openai")
    expect(CompletionKit.config.anthropic_api_key).to eq("configured-anthropic")
    expect(CompletionKit.config.ollama_api_key).to eq("configured-ollama")
    expect(CompletionKit.config.ollama_api_endpoint).to eq("https://ollama.example.test")
    expect(CompletionKit.config.judge_model).to eq("claude-3-7-sonnet-latest")

    expect { CompletionKit.configure }.not_to raise_error

    expect { silently_load(File.expand_path("../../lib/completion-kit.rb", __dir__)) }.not_to raise_error

    prompt = create(:completion_kit_prompt, name: "Smoke Prompt", family_key: "smoke-family", version_number: 1, template: "Hello {{name}}")
    expect(CompletionKit.current_prompt("Smoke Prompt")).to eq(prompt)
    expect(CompletionKit.current_prompt_payload("smoke-family")).to include(name: "Smoke Prompt", template: "Hello {{name}}")
    expect(CompletionKit.render_current_prompt("Smoke Prompt", name: "Avery")).to eq("Hello Avery")
  end

  it "initializes configuration defaults from ENV and registers the precompiled asset" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("env-openai")
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("env-anthropic")
    allow(ENV).to receive(:[]).with("OLLAMA_API_KEY").and_return("env-ollama")
    allow(ENV).to receive(:[]).with("OLLAMA_API_ENDPOINT").and_return("https://env-ollama.example.test")

    config = CompletionKit::Configuration.new

    expect(config.openai_api_key).to eq("env-openai")
    expect(config.anthropic_api_key).to eq("env-anthropic")
    expect(config.ollama_api_key).to eq("env-ollama")
    expect(config.ollama_api_endpoint).to eq("https://env-ollama.example.test")
    expect(config.judge_model).to eq("gpt-4.1")
    expect(config.high_quality_threshold).to eq(4)
    expect(config.medium_quality_threshold).to eq(3)

    asset_initializer = CompletionKit::Engine.initializers.find { |initializer| initializer.name == "completion_kit.assets" }
    assets = Struct.new(:precompile).new([])
    app = Struct.new(:config).new(Struct.new(:assets).new(assets))

    CompletionKit::Engine.register_assets(app)
    asset_initializer.block.call(app)

    expect(app.config.assets.precompile).to include("completion_kit/application.css")
  end
end
