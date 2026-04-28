require "rails_helper"

RSpec.describe "Prompt versioning and public API", type: :model do
  let!(:v1) do
    create(:completion_kit_prompt,
      name: "Summarizer", family_key: "sum-1", version_number: 1,
      template: "Summarize {{content}}", current: true)
  end
  let!(:v2) do
    create(:completion_kit_prompt,
      name: "Summarizer", family_key: "sum-1", version_number: 2,
      template: "Briefly summarize {{content}}", current: false, published_at: nil)
  end

  describe "Prompt#publish!" do
    it "makes the target version current and unpublishes others" do
      v2.publish!

      expect(v2.reload.current).to be true
      expect(v2.published_at).to be_present
      expect(v1.reload.current).to be false
    end

    it "supports rollback by publishing an older version" do
      v2.publish!
      v1.publish!

      expect(v1.reload.current).to be true
      expect(v2.reload.current).to be false
    end
  end

  describe "Prompt#clone_as_new_version" do
    it "creates a new version with incremented number" do
      v3 = v1.clone_as_new_version

      expect(v3.version_number).to eq(3)
      expect(v3.current).to be false
      expect(v3.family_key).to eq("sum-1")
      expect(v3.template).to eq(v1.template)
    end
  end

  describe "CompletionKit.current_prompt" do
    it "returns the current version by name" do
      result = CompletionKit.current_prompt("Summarizer")
      expect(result.id).to eq(v1.id)
    end

    it "returns the current version by family_key" do
      result = CompletionKit.current_prompt("sum-1")
      expect(result.id).to eq(v1.id)
    end

    it "returns updated current after publish" do
      v2.publish!
      result = CompletionKit.current_prompt("Summarizer")
      expect(result.id).to eq(v2.id)
    end
  end

  describe "CompletionKit.current_prompt_payload" do
    it "returns structured payload" do
      payload = CompletionKit.current_prompt_payload("Summarizer")

      expect(payload[:name]).to eq("Summarizer")
      expect(payload[:family_key]).to eq("sum-1")
      expect(payload[:version_number]).to eq(1)
      expect(payload[:template]).to eq("Summarize {{content}}")
      expect(payload[:generation_model]).to eq("gpt-4.1-mini")
    end
  end

  describe "CompletionKit.render_current_prompt" do
    it "substitutes variables into the current template" do
      result = CompletionKit.render_current_prompt("Summarizer", { "content" => "the news" })
      expect(result).to eq("Summarize the news")
    end
  end
end
