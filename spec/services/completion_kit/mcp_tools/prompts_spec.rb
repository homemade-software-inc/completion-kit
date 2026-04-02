require "rails_helper"

RSpec.describe CompletionKit::McpTools::Prompts do
  describe ".definitions" do
    it "returns 6 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(6)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        prompts_list prompts_get prompts_create prompts_update
        prompts_delete prompts_publish
      ])
    end

    it "includes inputSchema for each tool" do
      described_class.definitions.each do |tool|
        expect(tool[:inputSchema]).to be_a(Hash)
        expect(tool[:inputSchema][:type]).to eq("object")
      end
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt, name: "Test Prompt") }

    it "lists prompts" do
      result = described_class.call("prompts_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["name"]).to eq("Test Prompt")
    end

    it "gets a prompt by id" do
      result = described_class.call("prompts_get", {"id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(prompt.id)
    end

    it "creates a prompt" do
      result = described_class.call("prompts_create", {
        "name" => "New Prompt", "template" => "Hello {{name}}", "llm_model" => "gpt-4.1"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Prompt")
      expect(CompletionKit::Prompt.count).to eq(2)
    end

    it "updates a prompt" do
      result = described_class.call("prompts_update", {"id" => prompt.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "deletes a prompt" do
      result = described_class.call("prompts_delete", {"id" => prompt.id})
      expect(result[:content].first[:text]).to include("deleted")
      expect(CompletionKit::Prompt.count).to eq(0)
    end

    it "publishes a prompt" do
      result = described_class.call("prompts_publish", {"id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["current"]).to be true
    end

    it "auto-versions on update when prompt has runs" do
      create(:completion_kit_run, prompt: prompt)
      result = described_class.call("prompts_update", {"id" => prompt.id, "template" => "New {{content}}"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["version_number"]).to eq(2)
      expect(content["current"]).to be true
      expect(CompletionKit::Prompt.count).to eq(2)
    end

    it "returns error on invalid create" do
      result = described_class.call("prompts_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("prompts_update", {"id" => prompt.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error for unknown tool" do
      expect { described_class.call("prompts_bogus", {}) }.to raise_error(KeyError)
    end
  end
end
