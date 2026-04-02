require "rails_helper"

RSpec.describe CompletionKit::ProviderCredential, type: :model do
  before do
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
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

  describe "#model_pattern" do
    it "returns correct regex for each provider" do
      expect(build(:completion_kit_provider_credential, provider: "openai").model_pattern).to eq(/\Agpt-/)
      expect(build(:completion_kit_provider_credential, provider: "anthropic").model_pattern).to eq(/\Aclaude-/)
      expect(build(:completion_kit_provider_credential, provider: "llama").model_pattern).to eq(/llama/i)
    end

    it "returns nil for unknown provider" do
      cred = build(:completion_kit_provider_credential, provider: "openai")
      allow(cred).to receive(:provider).and_return("unknown")
      expect(cred.model_pattern).to be_nil
      expect(cred.prompt_count).to eq(0)
      expect(cred.judge_count).to eq(0)
      expect(cred.last_used_at).to be_nil
    end
  end

  describe "#prompt_count" do
    it "counts prompts using models from this provider" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      create(:completion_kit_prompt, llm_model: "gpt-4.1")
      create(:completion_kit_prompt, llm_model: "gpt-4.1-mini")
      create(:completion_kit_prompt, llm_model: "claude-3.5-sonnet")
      expect(credential.prompt_count).to eq(2)
    end

    it "returns 0 for prompts with nil llm_model" do
      credential = create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test")
      expect(credential.prompt_count).to eq(0)
    end

    it "handles prompts with nil llm_model gracefully" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1")
      prompt.update_column(:llm_model, nil)
      expect(credential.prompt_count).to eq(0)
    end
  end

  describe "#judge_count" do
    it "counts runs using judge models from this provider" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      create(:completion_kit_run, judge_model: "gpt-4.1")
      create(:completion_kit_run, judge_model: "claude-3.5-sonnet")
      create(:completion_kit_run, judge_model: nil)
      create(:completion_kit_run, judge_model: "")
      expect(credential.judge_count).to eq(1)
    end
  end

  describe "#last_used_at" do
    it "returns the most recent run time for this provider" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1")
      old_run = create(:completion_kit_run, prompt: prompt, status: "completed", created_at: 2.days.ago)
      recent_run = create(:completion_kit_run, prompt: prompt, status: "completed", created_at: 1.hour.ago)
      expect(credential.last_used_at).to be_within(1.second).of(recent_run.created_at)
    end

    it "returns nil when never used" do
      credential = create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test")
      expect(credential.last_used_at).to be_nil
    end

    it "finds runs where provider is used as judge" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "claude-3.5-sonnet")
      run = create(:completion_kit_run, prompt: prompt, judge_model: "gpt-4.1", status: "completed")
      expect(credential.last_used_at).to be_within(1.second).of(run.created_at)
    end

    it "handles runs with nil judge_model" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1")
      create(:completion_kit_run, prompt: prompt, judge_model: nil, status: "completed")
      expect(credential.last_used_at).not_to be_nil
    end

    it "handles runs where prompt has nil llm_model and nil judge_model" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "claude-3.5-sonnet")
      prompt.update_column(:llm_model, nil)
      create(:completion_kit_run, prompt: prompt, judge_model: nil, status: "completed")
      expect(credential.last_used_at).to be_nil
    end

    it "skips pending runs" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
      prompt = create(:completion_kit_prompt, llm_model: "gpt-4.1")
      create(:completion_kit_run, prompt: prompt, status: "pending")
      expect(credential.last_used_at).to be_nil
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
end
