require "rails_helper"

RSpec.describe CompletionKit::McpTools::Imports do
  let(:yaml) do
    <<~YAML
      prompts:
        - "Answer {{question}}."
      tests:
        - vars: { question: "What is 2+2?" }
      defaultTest:
        assert:
          - type: is-json
    YAML
  end

  describe ".definitions" do
    it "exposes the promptfoo_import tool" do
      expect(described_class.definitions.map { |d| d[:name] }).to include("promptfoo_import")
    end
  end

  describe "promptfoo_import" do
    it "imports a config and returns a summary" do
      result = described_class.call("promptfoo_import", { "config" => yaml })
      content = JSON.parse(result[:content].first[:text])

      expect(content["prompts"]["created"]).to eq(["Imported prompt 1"])
      expect(content["metrics"]["created"].first["type"]).to eq("check")
      expect(CompletionKit::Dataset.count).to eq(1)
    end

    it "returns an error result for unparseable YAML" do
      result = described_class.call("promptfoo_import", { "config" => "a: : :" })
      expect(result[:isError]).to be(true)
    end
  end
end
