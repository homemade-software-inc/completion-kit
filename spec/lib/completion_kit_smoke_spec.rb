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
      llama_key: CompletionKit.config.llama_api_key,
      llama_endpoint: CompletionKit.config.llama_api_endpoint,
      judge_model: CompletionKit.config.judge_model
    }

    example.run
  ensure
    CompletionKit.config.openai_api_key = original_values[:openai]
    CompletionKit.config.anthropic_api_key = original_values[:anthropic]
    CompletionKit.config.llama_api_key = original_values[:llama_key]
    CompletionKit.config.llama_api_endpoint = original_values[:llama_endpoint]
    CompletionKit.config.judge_model = original_values[:judge_model]
  end

  it "supports configuration, versioning, engine boot, and hyphenated require" do
    expect { silently_load(File.expand_path("../../lib/completion_kit/version.rb", __dir__)) }.not_to raise_error
    expect { silently_load(File.expand_path("../../lib/completion_kit/engine.rb", __dir__)) }.not_to raise_error
    expect { silently_load(File.expand_path("../../lib/completion_kit.rb", __dir__)) }.not_to raise_error

    expect(CompletionKit::VERSION).to eq("0.1.0")
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
      config.llama_api_key = "configured-llama"
      config.llama_api_endpoint = "https://llama.example.test"
      config.judge_model = "claude-3-7-sonnet-latest"
    end

    expect(CompletionKit.config.openai_api_key).to eq("configured-openai")
    expect(CompletionKit.config.anthropic_api_key).to eq("configured-anthropic")
    expect(CompletionKit.config.llama_api_key).to eq("configured-llama")
    expect(CompletionKit.config.llama_api_endpoint).to eq("https://llama.example.test")
    expect(CompletionKit.config.judge_model).to eq("claude-3-7-sonnet-latest")

    expect { CompletionKit.configure }.not_to raise_error

    expect { silently_load(File.expand_path("../../lib/completion-kit.rb", __dir__)) }.not_to raise_error

    metric_group = create(:completion_kit_metric_group, :with_metrics, metrics_count: 1)
    prompt = create(:completion_kit_prompt, name: "Smoke Prompt", family_key: "smoke-family", version_number: 1, template: "Hello {{name}}", metric_group: metric_group)
    expect(CompletionKit.current_prompt("Smoke Prompt")).to eq(prompt)
    expect(CompletionKit.current_prompt_payload("smoke-family")).to include(name: "Smoke Prompt", template: "Hello {{name}}", metric_group: metric_group.name)
    expect(CompletionKit.current_prompt_payload("smoke-family")[:metrics].first[:name]).to eq(metric_group.metrics.first.name)
    expect(CompletionKit.render_current_prompt("Smoke Prompt", name: "Avery")).to eq("Hello Avery")
  end

  it "returns a legacy metric payload when no metric group is attached" do
    prompt = create(:completion_kit_prompt, name: "Legacy Prompt", family_key: "legacy-family", metric_group: nil)

    payload = CompletionKit.current_prompt_payload("legacy-family")

    expect(payload[:metric_group]).to be_nil
    expect(payload[:metrics].first[:name]).to eq("Overall quality")
    expect(payload[:metrics].first[:rubric_bands].first["range"]).to eq("1-2")
  end

  it "uses raw rubric bands when a metric-like payload object does not expose rubric_bands_for_form" do
    prompt = create(:completion_kit_prompt, name: "Stub Prompt", family_key: "stub-family", metric_group: nil)
    metric_like = Struct.new(:name, :guidance_text, :rubric_text, :rubric_bands).new("Stub", "Guide", "Rubric", [{ "range" => "1-2" }])

    allow(CompletionKit).to receive(:current_prompt).with("stub-family").and_return(prompt)
    allow(prompt).to receive(:assessment_metrics).and_return([metric_like])

    expect(CompletionKit.current_prompt_payload("stub-family")[:metrics].first[:rubric_bands]).to eq([{ "range" => "1-2" }])
  end

  it "initializes configuration defaults from ENV and registers the precompiled asset" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("env-openai")
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("env-anthropic")
    allow(ENV).to receive(:[]).with("LLAMA_API_KEY").and_return("env-llama")
    allow(ENV).to receive(:[]).with("LLAMA_API_ENDPOINT").and_return("https://env-llama.example.test")

    config = CompletionKit::Configuration.new

    expect(config.openai_api_key).to eq("env-openai")
    expect(config.anthropic_api_key).to eq("env-anthropic")
    expect(config.llama_api_key).to eq("env-llama")
    expect(config.llama_api_endpoint).to eq("https://env-llama.example.test")
    expect(config.judge_model).to eq("gpt-4.1")
    expect(config.high_quality_threshold).to eq(8)
    expect(config.medium_quality_threshold).to eq(5)

    asset_initializer = CompletionKit::Engine.initializers.find { |initializer| initializer.name == "completion_kit.assets" }
    assets = Struct.new(:precompile).new([])
    app = Struct.new(:config).new(Struct.new(:assets).new(assets))

    CompletionKit::Engine.register_assets(app)
    asset_initializer.block.call(app)

    expect(app.config.assets.precompile).to include("completion_kit/application.css")
  end
end
