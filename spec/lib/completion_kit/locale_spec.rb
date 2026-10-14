require "rails_helper"

RSpec.describe "CompletionKit English locale" do
  it "is on the I18n load path through the engine" do
    expect(I18n.load_path.map(&:to_s)).to include(CompletionKit::Engine.root.join("config/locales/en.yml").to_s)
  end

  it "names attributes the way the UI does" do
    expect(CompletionKit::Prompt.human_attribute_name(:llm_model)).to eq("Model")
    expect(CompletionKit::Run.human_attribute_name(:judge_model)).to eq("Judge model")
    expect(CompletionKit::Run.human_attribute_name(:metric_ids)).to eq("Metrics")
    expect(CompletionKit::MetricGroup.human_attribute_name(:metric_ids)).to eq("Metrics")
    expect(CompletionKit::ProviderCredential.human_attribute_name(:api_key)).to eq("API key")
  end
end
