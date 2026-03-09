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
      expect(helper.ck_badge_classes(:completed)).to include("ck-badge--high")
      expect(helper.ck_badge_classes(:failed)).to include("ck-badge--low")
      expect(helper.ck_badge_classes(:mystery)).to include("ck-badge--pending")
    end
  end

  describe "#ck_score_kind" do
    it "returns the expected score bands" do
      expect(helper.ck_score_kind(nil)).to eq(:pending)
      expect(helper.ck_score_kind(9.5)).to eq(:high)
      expect(helper.ck_score_kind(6.0)).to eq(:medium)
      expect(helper.ck_score_kind(2.0)).to eq(:low)
    end
  end
end
