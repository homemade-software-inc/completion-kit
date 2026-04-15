require "rails_helper"

RSpec.describe CompletionKit::ApplicationHelper, type: :helper do
  describe "#ck_button_classes" do
    it "covers every button style branch" do
      expect(helper.ck_button_classes(:dark)).to include("ck-button--primary")
      expect(helper.ck_button_classes(:light, variant: :outline)).to include("ck-button--secondary")
      expect(helper.ck_button_classes(:green)).to include("ck-button--success")
      expect(helper.ck_button_classes(:red, variant: :outline)).to include("ck-button--danger")
      expect(helper.ck_button_classes(:amber, variant: :outline)).to include("ck-button--warning")
      expect(helper.ck_button_classes(:blue, variant: :outline)).to include("ck-button--info")
      expect(helper.ck_button_classes(:unknown, variant: :ghost)).to include("ck-button--primary")
    end
  end

  describe "#ck_badge_classes" do
    it "covers every badge style branch" do
      expect(helper.ck_badge_classes(:high)).to include("ck-badge--high")
      expect(helper.ck_badge_classes(:medium)).to include("ck-badge--medium")
      expect(helper.ck_badge_classes(:low)).to include("ck-badge--low")
      expect(helper.ck_badge_classes(:pending)).to include("ck-badge--pending")
      expect(helper.ck_badge_classes(:running)).to include("ck-badge--running")
      expect(helper.ck_badge_classes(:generating)).to include("ck-badge--running")
      expect(helper.ck_badge_classes(:judging)).to include("ck-badge--running")
      expect(helper.ck_badge_classes(:completed)).to include("ck-badge--high")
      expect(helper.ck_badge_classes(:failed)).to include("ck-badge--low")
      expect(helper.ck_badge_classes(:mystery)).to include("ck-badge--pending")
    end
  end

  describe "#ck_run_dot" do
    def stub_run(status)
      instance_double(CompletionKit::Run, status: status)
    end

    it "returns pending dot for pending status" do
      expect(helper.ck_run_dot(stub_run("pending"))).to eq("ck-dot ck-dot--pending")
    end

    it "returns running dot for generating status" do
      expect(helper.ck_run_dot(stub_run("generating"))).to eq("ck-dot ck-dot--running")
    end

    it "returns running dot for judging status" do
      expect(helper.ck_run_dot(stub_run("judging"))).to eq("ck-dot ck-dot--running")
    end

    it "returns failed dot for failed status" do
      expect(helper.ck_run_dot(stub_run("failed"))).to eq("ck-dot ck-dot--failed")
    end

    it "returns completed dot for completed status" do
      expect(helper.ck_run_dot(stub_run("completed"))).to eq("ck-dot ck-dot--completed")
    end

    it "returns pending dot for unknown status" do
      expect(helper.ck_run_dot(stub_run("unknown_state"))).to eq("ck-dot ck-dot--pending")
    end
  end

  describe "#ck_grouped_models" do
    it "returns grouped options for select" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-4")
      expect(result).to include("GPT-4")
      expect(result).to include("OpenAI")
    end

    it "appends retired model when selected model is not in list" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-old", display_name: "GPT Old", status: "retired")
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-old")
      expect(result).to include("GPT Old (retired)")
    end

    it "does not append when selected model is already present" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "gpt-4")
      expect(result).not_to include("retired")
    end

    it "handles selected model not found in registry" do
      models = [{ id: "gpt-4", name: "GPT-4", provider: "openai" }]
      result = helper.ck_grouped_models(models, "nonexistent")
      expect(result).not_to include("retired")
    end
  end

  describe "#ck_grouped_models with openrouter" do
    it "splits openrouter models into optgroups by upstream namespace" do
      models = [
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
        { id: "openai/gpt-4o-mini", name: "GPT-4o Mini", provider: "openrouter" },
        { id: "openai/gpt-5", name: "GPT-5", provider: "openrouter" },
        { id: "anthropic/claude-sonnet", name: "Claude Sonnet", provider: "openrouter" },
        { id: "meta-llama/llama-3.3-70b", name: "Llama 3.3 70B", provider: "openrouter" }
      ]
      html = helper.ck_grouped_models(models)
      expect(html).to include('label="OpenAI"')
      expect(html).to include('label="OpenRouter — openai"')
      expect(html).to include('label="OpenRouter — anthropic"')
      expect(html).to include('label="OpenRouter — meta-llama"')
    end

    it "groups direct providers as before" do
      models = [
        { id: "gpt-4.1-mini", name: "GPT-4.1 Mini", provider: "openai" },
        { id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "anthropic" }
      ]
      html = helper.ck_grouped_models(models)
      expect(html).to include('label="OpenAI"')
      expect(html).to include('label="Anthropic"')
    end
  end

  describe "#ck_model_options_html" do
    it "returns empty string when no models exist for scope" do
      result = helper.ck_model_options_html(:generation)
      expect(result).to eq("")
    end

    it "returns grouped options html when models exist for scope" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-test", supports_generation: true, status: "active")
      result = helper.ck_model_options_html(:generation)
      expect(result).to include("gpt-test")
    end
  end

  describe "#ck_score_kind" do
    it "returns the expected score bands" do
      expect(helper.ck_score_kind(nil)).to eq(:pending)
      expect(helper.ck_score_kind(4.5)).to eq(:high)
      expect(helper.ck_score_kind(3.5)).to eq(:medium)
      expect(helper.ck_score_kind(2.0)).to eq(:low)
    end
  end

  describe "#ck_run_status_label" do
    def stub_run(status, progress_current: 0, progress_total: 0)
      instance_double(CompletionKit::Run, status: status, progress_current: progress_current, progress_total: progress_total)
    end

    it "returns Ready to run for pending" do
      expect(helper.ck_run_status_label(stub_run("pending"))).to eq("Ready to run")
    end

    it "returns generating with progress when progress_total > 0" do
      expect(helper.ck_run_status_label(stub_run("generating", progress_current: 3, progress_total: 10))).to eq("Generating responses (3/10)")
    end

    it "returns generating without progress when progress_total is 0" do
      expect(helper.ck_run_status_label(stub_run("generating", progress_total: 0))).to include("Generating")
    end

    it "returns judging with progress when progress_total > 0" do
      expect(helper.ck_run_status_label(stub_run("judging", progress_current: 2, progress_total: 8))).to eq("Judging (2/8 evaluations)")
    end

    it "returns judging without progress when progress_total is 0" do
      expect(helper.ck_run_status_label(stub_run("judging", progress_total: 0))).to include("Judging")
    end

    it "returns Completed for completed" do
      expect(helper.ck_run_status_label(stub_run("completed"))).to eq("Completed")
    end

    it "returns Failed for failed" do
      expect(helper.ck_run_status_label(stub_run("failed"))).to eq("Failed")
    end

    it "capitalizes unknown statuses" do
      expect(helper.ck_run_status_label(stub_run("mystery"))).to eq("Mystery")
    end
  end

  describe "#ck_word_diff_old" do
    it "marks removed words in old text and skips additions" do
      result = helper.ck_word_diff_old("hello world", "hello universe")
      expect(result).to include("ck-diff-del")
      expect(result).to include("world")
      expect(result).not_to include("ck-diff-ins")
    end

    it "returns unchanged text when texts are identical" do
      result = helper.ck_word_diff_old("hello world", "hello world")
      expect(result).not_to include("ck-diff")
      expect(result).to include("hello")
    end
  end

  describe "#ck_word_diff_new" do
    it "marks added words in new text and skips removals" do
      result = helper.ck_word_diff_new("hello world", "hello universe")
      expect(result).to include("ck-diff-ins")
      expect(result).to include("universe")
      expect(result).not_to include("ck-diff-del")
    end

    it "handles nil inputs" do
      result = helper.ck_word_diff_new(nil, "hello")
      expect(result).to include("hello")
    end
  end
end
