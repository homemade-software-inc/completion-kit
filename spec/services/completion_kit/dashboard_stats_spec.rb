require "rails_helper"

RSpec.describe CompletionKit::DashboardStats, type: :service do
  describe ".activity" do
    it "returns one entry per day, oldest first, with zero-filled quiet days" do
      create(:completion_kit_run, created_at: 2.days.ago)
      create(:completion_kit_run, created_at: 2.days.ago)
      create(:completion_kit_run, created_at: Time.current)

      activity = described_class.activity(days: 5)

      expect(activity.length).to eq(5)
      expect(activity.map { |d| d[:date] }).to eq(activity.map { |d| d[:date] }.sort)
      expect(activity.last[:count]).to eq(1)
      expect(activity.find { |d| d[:date] == 2.days.ago.to_date }[:count]).to eq(2)
      expect(activity.sum { |d| d[:count] }).to eq(3)
    end

    it "excludes runs older than the window" do
      create(:completion_kit_run, created_at: 40.days.ago)
      expect(described_class.activity(days: 7).sum { |d| d[:count] }).to eq(0)
    end
  end

  describe ".worst_metric" do
    it "returns nil when there are no scored reviews" do
      expect(described_class.worst_metric(since: 7.days.ago)).to be_nil
    end

    it "surfaces the lowest-average metric and its worst-scoring response" do
      strong = create(:completion_kit_response)
      weak_a = create(:completion_kit_response)
      weak_b = create(:completion_kit_response)
      create(:completion_kit_review, response: strong, metric_name: "Accuracy", ai_score: 5.0)
      create(:completion_kit_review, response: weak_a, metric_name: "Brevity", ai_score: 2.0)
      create(:completion_kit_review, response: weak_b, metric_name: "Brevity", ai_score: 1.0)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:name]).to eq("Brevity")
      expect(result[:avg]).to eq(1.5)
      expect(result[:score]).to eq(1.0)
      expect(result[:response]).to eq(weak_b)
    end

    it "ignores failed reviews and reviews outside the window" do
      recent = create(:completion_kit_response)
      old = create(:completion_kit_response)
      create(:completion_kit_review, response: recent, metric_name: "Accuracy", ai_score: 4.0)
      create(:completion_kit_review, response: recent, metric_name: "Failed", status: "failed", ai_score: nil)
      create(:completion_kit_review, response: old, metric_name: "Stale", ai_score: 1.0, created_at: 40.days.ago)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:name]).to eq("Accuracy")
    end
  end

  describe ".failed_review_count" do
    it "counts only failed reviews inside the window" do
      response = create(:completion_kit_response)
      create(:completion_kit_review, response: response, status: "failed", ai_score: nil)
      create(:completion_kit_review, response: response, status: "failed", ai_score: nil, created_at: 40.days.ago)
      create(:completion_kit_review, response: response, status: "succeeded", ai_score: 4.0)

      expect(described_class.failed_review_count(since: 7.days.ago)).to eq(1)
    end
  end

  describe ".prompt_changes" do
    # Builds a prompt version with one scored run; returns the prompt.
    def scored_version(family:, version:, score:, current: false)
      prompt = create(:completion_kit_prompt, family_key: family, version_number: version, current: current)
      response = create(:completion_kit_response, run: create(:completion_kit_run, prompt: prompt))
      create(:completion_kit_review, response: response, ai_score: score)
      prompt
    end

    it "is empty when there are no scored reviews" do
      expect(described_class.prompt_changes).to eq([])
    end

    it "ignores families with only one scored version" do
      scored_version(family: "solo", version: 1, score: 3.0)
      expect(described_class.prompt_changes).to eq([])
    end

    it "compares the latest draft against the published version when a draft sits ahead" do
      scored_version(family: "fam", version: 1, score: 3.0, current: true)
      draft = scored_version(family: "fam", version: 2, score: 4.5)

      result = described_class.prompt_changes

      expect(result.length).to eq(1)
      expect(result.first).to include(
        prompt: draft, from_version: 1, to_version: 2,
        from_score: 3.0, to_score: 4.5, delta: 1.5
      )
    end

    it "compares the published version against the previous one when latest is published" do
      scored_version(family: "fam", version: 1, score: 4.0)
      published = scored_version(family: "fam", version: 2, score: 3.0, current: true)

      result = described_class.prompt_changes

      expect(result.first).to include(prompt: published, from_version: 1, to_version: 2, delta: -1.0)
    end

    it "surfaces regressions as negative deltas" do
      scored_version(family: "regressed", version: 1, score: 4.0, current: true)
      scored_version(family: "regressed", version: 2, score: 2.0)

      result = described_class.prompt_changes

      expect(result.first[:delta]).to eq(-2.0)
    end

    it "skips families where the change nets to zero" do
      scored_version(family: "flat", version: 1, score: 3.0, current: true)
      scored_version(family: "flat", version: 2, score: 3.0)
      expect(described_class.prompt_changes).to eq([])
    end

    it "falls back to the previous scored version when the published one was never scored" do
      v1 = create(:completion_kit_prompt, family_key: "gap", version_number: 1, current: false)
      r1 = create(:completion_kit_response, run: create(:completion_kit_run, prompt: v1))
      create(:completion_kit_review, response: r1, ai_score: 2.0)
      # published v2 has no scored reviews
      create(:completion_kit_prompt, family_key: "gap", version_number: 2, current: true)
      v3 = create(:completion_kit_prompt, family_key: "gap", version_number: 3, current: false)
      r3 = create(:completion_kit_response, run: create(:completion_kit_run, prompt: v3))
      create(:completion_kit_review, response: r3, ai_score: 4.0)

      result = described_class.prompt_changes

      expect(result.first).to include(prompt: v3, from_version: 1, to_version: 3, delta: 2.0)
    end

    it "falls back to the last two scored versions when no version is published" do
      scored_version(family: "draftonly", version: 1, score: 2.0)
      latest = scored_version(family: "draftonly", version: 2, score: 3.5)

      result = described_class.prompt_changes

      expect(result.first).to include(prompt: latest, from_version: 1, to_version: 2, delta: 1.5)
    end

    it "sorts by the biggest movement first and honours the limit" do
      scored_version(family: "small", version: 1, score: 3.0, current: true)
      scored_version(family: "small", version: 2, score: 3.3)
      scored_version(family: "big", version: 1, score: 4.5, current: true)
      scored_version(family: "big", version: 2, score: 1.5)

      result = described_class.prompt_changes(limit: 1)

      expect(result.length).to eq(1)
      expect(result.first[:delta]).to eq(-3.0)
    end
  end
end
