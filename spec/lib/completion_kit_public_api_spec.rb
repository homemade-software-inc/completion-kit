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
end
