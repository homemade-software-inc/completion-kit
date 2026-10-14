require "rails_helper"

RSpec.describe CompletionKit::Prompt, type: :model do
  describe "template size limit" do
    around do |example|
      original = CompletionKit.config.max_template_bytes
      CompletionKit.config.max_template_bytes = 512 * 1024
      example.run
    ensure
      CompletionKit.config.max_template_bytes = original
    end

    it "rejects a template larger than the configured limit" do
      prompt = build(:completion_kit_prompt, template: "x" * ((512 * 1024) + 1))

      expect(prompt).not_to be_valid
      expect(prompt.errors[:template]).to eq(["is too large (limit 512 KB)"])
    end

    it "counts bytes, so a multibyte template under the limit in characters can still exceed it" do
      prompt = build(:completion_kit_prompt, template: "é" * ((256 * 1024) + 1))

      expect(prompt).not_to be_valid
      expect(prompt.errors[:template]).to eq(["is too large (limit 512 KB)"])
    end

    it "accepts a template at the limit" do
      expect(build(:completion_kit_prompt, template: "x" * (512 * 1024))).to be_valid
    end

    it "keeps an existing prompt saveable when the limit drops below its unchanged template" do
      prompt = create(:completion_kit_prompt, template: "x" * 100)
      CompletionKit.config.max_template_bytes = 32

      expect(prompt.update(name: "Renamed")).to be(true)
      expect(prompt.update(template: "y" * 100)).to be(false)
      expect(prompt.errors[:template]).to eq(["is too large (limit 32 Bytes)"])
    end
  end

  describe "destroy cascade" do
    it "destroys runs, responses, and reviews; other versions of the family are untouched" do
      v1 = create(:completion_kit_prompt, name: "Family", family_key: "fam-cascade", version_number: 1, template: "Static prompt without variables")
      v2 = create(:completion_kit_prompt, name: "Family", family_key: "fam-cascade", version_number: 2, template: "Static prompt without variables")
      run = create(:completion_kit_run, prompt: v1)
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: response)

      expect { v1.destroy! }
        .to change(CompletionKit::Run, :count).by(-1)
        .and change(CompletionKit::Response, :count).by(-1)
        .and change(CompletionKit::Review, :count).by(-1)

      expect(CompletionKit::Prompt.exists?(v2.id)).to be(true)
    end
  end

  it "exposes the available model list" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    expect(described_class.available_models).to include(hash_including(id: "gpt-5.4-mini"))
  end

  describe "llm_model generation-usability validation" do
    it "rejects a model that is known not to support generation" do
      CompletionKit::Model.create!(provider: "azure_foundry", model_id: "catalog-only",
        status: "active", supports_generation: false, supports_judging: false)
      prompt = build(:completion_kit_prompt, llm_model: "catalog-only")

      expect(prompt).not_to be_valid
      expect(prompt.errors[:llm_model]).to include("is not available for generating responses")
    end

    it "allows a model that has not been probed yet" do
      CompletionKit::Model.create!(provider: "azure_foundry", model_id: "unprobed",
        status: "active", supports_generation: nil, supports_judging: nil)

      expect(build(:completion_kit_prompt, llm_model: "unprobed")).to be_valid
    end

    it "allows a model_id the tool has never discovered" do
      expect(build(:completion_kit_prompt, llm_model: "totally-unknown-model")).to be_valid
    end

    it "does not re-validate an unchanged model when other attributes change" do
      prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
      CompletionKit::Model.where(model_id: "gpt-4.1-mini").update_all(supports_generation: false)

      prompt.template = "Updated {{content}} here"
      expect(prompt).to be_valid
    end

    it "allows re-versioning a prompt whose in-use model was demoted after the fact" do
      CompletionKit::Model.create!(provider: "openai", model_id: "kept-model",
        status: "active", supports_generation: true, supports_judging: true)
      original = create(:completion_kit_prompt, llm_model: "kept-model")
      CompletionKit::Model.where(model_id: "kept-model").update_all(supports_generation: false)

      clone = original.clone_as_new_version(template: "New {{content}} version")

      expect(clone).to be_persisted
      expect(clone.llm_model).to eq("kept-model")
    end

    context "when generation models have been discovered" do
      before do
        allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
        create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
        create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1-mini")
        create(:completion_kit_model, provider: "ollama", model_id: "llama3", status: "retired")
      end

      %w[llama3 ollama/llama3 ollama].each do |model_id|
        it "rejects #{model_id.inspect}, which no configured provider serves" do
          prompt = build(:completion_kit_prompt, llm_model: model_id)

          expect(prompt).not_to be_valid
          expect(prompt.errors.full_messages).to include(%(Model "#{model_id}" is not served by any configured provider))
        end
      end

      it "accepts an undiscovered id whose prefix belongs to a configured provider" do
        expect(build(:completion_kit_prompt, llm_model: "gpt-undiscovered")).to be_valid
      end

      it "keeps loading and editing a prompt whose model was retired after it was saved" do
        prompt = create(:completion_kit_prompt)
        prompt.update_columns(llm_model: "llama3")

        prompt.template = "Updated {{content}} for {{audience}}"
        expect(prompt).to be_valid
      end
    end

    it "still blocks re-versioning onto a different model that can't generate" do
      CompletionKit::Model.create!(provider: "azure_foundry", model_id: "switch-target",
        status: "active", supports_generation: false, supports_judging: false)
      original = create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")

      expect { original.clone_as_new_version(llm_model: "switch-target") }
        .to raise_error(ActiveRecord::RecordInvalid, /not available for generating responses/)
    end
  end

  it "extracts variables from the template" do
    prompt = build(:completion_kit_prompt, template: "Hello {{ name }} and {{audience}}")

    expect(prompt.variables).to eq(%w[name audience])
  end

  it "finds a prompt by slug fallback in current_for" do
    prompt = create(
      :completion_kit_prompt,
      name: "My Cool Prompt",
      family_key: "unrelated-key",
      version_number: 1
    )

    expect(described_class.current_for("my-cool-prompt")).to eq(prompt)
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
    expect(prompt.display_name).to eq("Family Prompt · v1")

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

  describe "#llm_model_provider" do
    it "returns openai for a gpt-4 model" do
      prompt = build(:completion_kit_prompt, llm_model: "gpt-4o")
      expect(prompt.llm_model_provider).to eq("openai")
    end

    it "returns anthropic for a claude-3 model" do
      prompt = build(:completion_kit_prompt, llm_model: "claude-3-5-sonnet-20241022")
      expect(prompt.llm_model_provider).to eq("anthropic")
    end

    it "returns nil for an unknown model" do
      prompt = build(:completion_kit_prompt, llm_model: "totally-made-up-model")
      expect(prompt.llm_model_provider).to be_nil
    end
  end
end
