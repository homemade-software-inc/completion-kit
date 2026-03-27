require "rails_helper"

RSpec.describe CompletionKit::McpTools::Responses do
  describe ".definitions" do
    it "returns 2 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(2)
      expect(defs.map { |d| d[:name] }).to match_array(%w[responses_list responses_get])
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt) }
    let!(:run) { create(:completion_kit_run, prompt: prompt) }
    let!(:response_record) { create(:completion_kit_response, run: run, response_text: "Hello") }

    it "lists responses for a run" do
      result = described_class.call("responses_list", {"run_id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["response_text"]).to eq("Hello")
    end

    it "gets a response by id" do
      result = described_class.call("responses_get", {"run_id" => run.id, "id" => response_record.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(response_record.id)
    end
  end
end
