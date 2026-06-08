require "rails_helper"

RSpec.describe CompletionKit::McpTools::Prompts do
  describe ".definitions" do
    it "returns 7 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(7)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        prompts_list prompts_get prompts_create prompts_update
        prompts_delete prompts_publish prompts_suggest_improvement
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

    it "suggests a prompt improvement from a run and persists a Suggestion" do
      run = create(:completion_kit_run, prompt: prompt)
      allow_any_instance_of(CompletionKit::PromptImprovementService).to receive(:suggest).and_return(
        "reasoning" => "tighten the ask",
        "suggested_template" => "Summarize clearly: {{content}}",
        "original_template" => prompt.template
      )

      result = nil
      expect {
        result = described_class.call("prompts_suggest_improvement", {"run_id" => run.id})
      }.to change(CompletionKit::Suggestion, :count).by(1)

      payload = JSON.parse(result[:content].first[:text])
      expect(payload["reasoning"]).to eq("tighten the ask")
      expect(payload["suggested_template"]).to eq("Summarize clearly: {{content}}")
      expect(payload["suggestion_id"]).to eq(CompletionKit::Suggestion.last.id)
    end

    it "returns isError for a judge-only run with no prompt to improve" do
      judge_run = create(:completion_kit_run, prompt: nil, output_column: "expected_output")

      result = described_class.call("prompts_suggest_improvement", {"run_id" => judge_run.id})

      expect(result[:isError]).to be(true)
      expect(CompletionKit::Suggestion.count).to eq(0)
    end

    it "round-trips tag_names on prompts_create with auto-create" do
      expect do
        described_class.call("prompts_create",
          {"name" => "Tagged", "template" => "Hi {{name}}", "llm_model" => "gpt-4.1", "tag_names" => ["fresh"]})
      end.to change(CompletionKit::Tag, :count).by(1)
      found = CompletionKit::Prompt.find_by!(name: "Tagged")
      expect(found.tag_names).to eq(["fresh"])
    end

    it "replaces tag_names on prompts_update" do
      prompt.update!(tag_names: ["a", "b"])
      described_class.call("prompts_update", {"id" => prompt.id, "tag_names" => ["c"]})
      expect(prompt.reload.tag_names).to eq(["c"])
    end

    it "applies tag_names when update clones as new version" do
      create(:completion_kit_run, prompt: prompt)
      described_class.call("prompts_update",
        {"id" => prompt.id, "template" => "New {{content}}", "tag_names" => ["versioned"]})
      new_prompt = CompletionKit::Prompt.order(created_at: :desc).first
      expect(new_prompt.version_number).to eq(2)
      expect(new_prompt.tag_names).to eq(["versioned"])
    end
  end
end
