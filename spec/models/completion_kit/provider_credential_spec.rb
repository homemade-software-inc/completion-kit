require "rails_helper"

RSpec.describe CompletionKit::ProviderCredential, type: :model do
  before do
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
  end

  describe "PROVIDERS and PROVIDER_LABELS" do
    it "includes openrouter as a valid provider" do
      expect(CompletionKit::ProviderCredential::PROVIDERS).to include("openrouter")
    end

    it "labels openrouter as 'OpenRouter'" do
      expect(CompletionKit::ProviderCredential::PROVIDER_LABELS["openrouter"]).to eq("OpenRouter")
    end

    it "labels llama as 'Llama / Ollama / Custom endpoint'" do
      expect(CompletionKit::ProviderCredential::PROVIDER_LABELS["llama"]).to eq("Llama / Ollama / Custom endpoint")
    end

    it "validates that provider is in the PROVIDERS list" do
      cred = CompletionKit::ProviderCredential.new(provider: "openrouter", api_key: "or-test")
      expect(cred).to be_valid
    end
  end

  it "returns config data and delegates to the provider client" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "secret")
    client = instance_double(CompletionKit::OpenAiClient, available_models: [{ id: "gpt-4.1" }], configured?: true)

    allow(CompletionKit::LlmClient).to receive(:for_provider).with("openai", hash_including(api_key: "secret", provider: "openai")).and_return(client)

    expect(credential.config_hash).to eq(provider: "openai", api_key: "secret")
    expect(credential.available_models).to eq([{ id: "gpt-4.1" }])
    expect(credential.configured?).to eq(true)
  end

  it "returns safe defaults when the client raises" do
    credential = create(:completion_kit_provider_credential, provider: "anthropic", api_key: "secret")

    allow(CompletionKit::LlmClient).to receive(:for_provider).and_raise(StandardError, "boom")

    expect(credential.available_models).to eq([])
    expect(credential.configured?).to eq(false)
  end

  describe "#enqueue_discovery (after_save callback)" do
    it "enqueues ModelDiscoveryJob on save" do
      expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(kind_of(Integer))
      create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    end

    it "enqueues for all providers including anthropic" do
      expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(kind_of(Integer))
      create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test")
    end

    it "enqueues for llama provider" do
      expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(kind_of(Integer))
      create(:completion_kit_provider_credential, provider: "llama", api_key: "sk-test")
    end
  end

  describe "credential counters" do
    let(:openai_cred) { create(:completion_kit_provider_credential, provider: "openai", api_key: "test") }

    before do
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-4.1-mini",
        status: "active", supports_generation: true, supports_judging: true)
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-5.4-mini",
        status: "active", supports_generation: true)
      CompletionKit::Model.create!(provider: "anthropic", model_id: "claude-sonnet-4-6",
        status: "active", supports_generation: true)
    end

    describe "#prompt_count" do
      it "counts prompts whose llm_model is in the provider's discovered Model table" do
        create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
        create(:completion_kit_prompt, llm_model: "gpt-5.4-mini")
        create(:completion_kit_prompt, llm_model: "claude-sonnet-4-6")
        expect(openai_cred.prompt_count).to eq(2)
      end

      it "counts only current prompt versions" do
        family_key = SecureRandom.hex(8)
        create(:completion_kit_prompt, llm_model: "gpt-4.1-mini",
          family_key: family_key, version_number: 1, current: false)
        create(:completion_kit_prompt, llm_model: "gpt-4.1-mini",
          family_key: family_key, version_number: 2, current: true)
        expect(openai_cred.prompt_count).to eq(1)
      end

      it "returns 0 when no models match the provider" do
        expect(openai_cred.prompt_count).to eq(0)
      end
    end

    describe "#judge_count" do
      it "counts runs whose judge_model is in the provider's Model table" do
        prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
        create(:completion_kit_run, prompt: prompt, judge_model: "gpt-5.4-mini")
        create(:completion_kit_run, prompt: prompt, judge_model: "claude-sonnet-4-6")
        expect(openai_cred.judge_count).to eq(1)
      end
    end

    describe "#last_used_at" do
      it "returns the timestamp of the most recent non-pending run using this provider" do
        prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
        create(:completion_kit_run, prompt: prompt, status: "completed",
          created_at: 2.days.ago)
        new_run = create(:completion_kit_run, prompt: prompt, status: "completed",
          created_at: 1.hour.ago)
        expect(openai_cred.last_used_at).to be_within(1.second).of(new_run.created_at)
      end

      it "ignores pending runs" do
        prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
        create(:completion_kit_run, prompt: prompt, status: "pending", created_at: 1.minute.ago)
        expect(openai_cred.last_used_at).to be_nil
      end

      it "returns nil when no runs use this provider's models" do
        expect(openai_cred.last_used_at).to be_nil
      end
    end
  end

  describe "#broadcast_discovery_progress" do
    it "broadcasts replace with discovery status partial" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      expect(credential).to receive(:broadcast_replace_to).with(
        "completion_kit_provider_#{credential.id}",
        target: "discovery_status_#{credential.id}",
        html: kind_of(String)
      )
      credential.broadcast_discovery_progress
    end
  end

  describe "#broadcast_discovery_complete" do
    it "delegates to broadcast_discovery_progress and broadcast_model_dropdowns" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      expect(credential).to receive(:broadcast_discovery_progress)
      expect(credential).to receive(:broadcast_model_dropdowns)
      credential.broadcast_discovery_complete
    end
  end

  describe "#broadcast_model_dropdowns" do
    it "broadcasts replacement HTML for model selects" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")

      expect(Turbo::StreamsChannel).to receive(:broadcast_action_to).with(
        "completion_kit_provider_#{credential.id}",
        action: :replace,
        target: "prompt_llm_model",
        html: kind_of(String)
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_action_to).with(
        "completion_kit_provider_#{credential.id}",
        action: :replace,
        target: "run_judge_model",
        html: kind_of(String)
      )

      credential.send(:broadcast_model_dropdowns)
    end
  end
end
