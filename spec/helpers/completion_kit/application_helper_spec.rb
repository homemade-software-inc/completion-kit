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
    def stub_run(status, avg_score: nil)
      instance_double(CompletionKit::Run, status: status, avg_score: avg_score)
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

    it "returns score-based dot for completed status with a score" do
      result = helper.ck_run_dot(stub_run("completed", avg_score: 4.5))
      expect(result).to eq("ck-dot ck-dot--high")
    end

    it "returns completed dot for completed status without a score" do
      expect(helper.ck_run_dot(stub_run("completed", avg_score: nil))).to eq("ck-dot ck-dot--completed")
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
end
