require "rails_helper"

RSpec.describe CompletionKit do
  it "exposes the current prompt payload and renders the current prompt" do
    load File.expand_path("../../lib/completion_kit.rb", __dir__)
    prompt = create(:completion_kit_prompt, name: "Public Prompt", family_key: "public-family", version_number: 1, template: "Hello {{name}}")

    expect(described_class.current_prompt("Public Prompt")).to eq(prompt)
    expect(described_class.current_prompt_payload("public-family")).to include(
      name: "Public Prompt",
      family_key: "public-family",
      version_number: 1,
      template: "Hello {{name}}",
      generation_model: prompt.llm_model
    )
    expect(described_class.render_current_prompt("Public Prompt", name: "Taylor")).to eq("Hello Taylor")
  end

  describe ".render_current_prompt with caller-supplied values" do
    before do
      create(:completion_kit_prompt, name: "Literal Prompt", family_key: "literal-family", version_number: 1, template: "A {{q}} B")
    end

    [
      "C:\\\\Users\\\\share",
      "match \\0 here",
      "match \\& here",
      "C:\\Users\\1a",
      "\\'",
      "\\`",
      "named \\k<x> group"
    ].each do |value|
      it "renders #{value.inspect} exactly as written" do
        expect(described_class.render_current_prompt("Literal Prompt", q: value)).to eq("A #{value} B")
      end
    end

    it "does not pull another variable into a value that names it" do
      expect(described_class.render_current_prompt("Literal Prompt", q: "{{secret}}", secret: "s3cr3t")).to eq("A {{secret}} B")
      expect(described_class.render_current_prompt("Literal Prompt", secret: "s3cr3t", q: "{{secret}}")).to eq("A {{secret}} B")
    end
  end
end
