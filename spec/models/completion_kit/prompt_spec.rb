require "rails_helper"

RSpec.describe CompletionKit::Prompt, type: :model do
  it "exposes the available model list" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    expect(described_class.available_models).to include(hash_including(id: "gpt-5.4-mini"))
  end

  it "extracts variables from the template" do
    prompt = build(:completion_kit_prompt, template: "Hello {{ name }} and {{audience}}")

    expect(prompt.variables).to eq(%w[name audience])
  end

  it "supports current lookup, display helpers, cloning, and publishing" do
    prompt = create(
      :completion_kit_prompt,
      name: "Family Prompt",
      family_key: "family-a",
      version_number: 1
    )

    expect(described_class.current_for("Family Prompt")).to eq(prompt)
    expect(described_class.current_for("family-a")).to eq(prompt)
    expect(prompt.version_label).to eq("v1")
    expect(prompt.display_name).to eq("Family Prompt — v1")

    clone = prompt.clone_as_new_version(template: "Updated {{content}}")
    expect(clone.version_number).to eq(2)
    expect(clone.current).to eq(false)

    clone.publish!
    expect(prompt.reload.current).to eq(false)
    expect(clone.reload.current).to eq(true)
  end

  it "defaults current state" do
    prompt = create(:completion_kit_prompt, current: nil)

    expect(prompt.current).to eq(true)
  end
end
