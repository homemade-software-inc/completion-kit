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

    it "surfaces the lowest-average metric, its record, and its worst-scoring response" do
      accuracy = create(:completion_kit_metric, name: "Accuracy")
      brevity = create(:completion_kit_metric, name: "Brevity")
      strong = create(:completion_kit_response)
      weak_a = create(:completion_kit_response)
      weak_b = create(:completion_kit_response)
      create(:completion_kit_review, response: strong, metric: accuracy, ai_score: 5.0)
      create(:completion_kit_review, response: weak_a, metric: brevity, ai_score: 2.0)
      create(:completion_kit_review, response: weak_b, metric: brevity, ai_score: 1.0)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:metric]).to eq(brevity)
      expect(result[:name]).to eq("Brevity")
      expect(result[:avg]).to eq(1.5)
      expect(result[:score]).to eq(1.0)
      expect(result[:response]).to eq(weak_b)
    end

    it "ignores failed reviews, out-of-window reviews, and reviews with no metric" do
      accuracy = create(:completion_kit_metric, name: "Accuracy")
      stale = create(:completion_kit_metric, name: "Stale")
      recent = create(:completion_kit_response)
      old = create(:completion_kit_response)
      create(:completion_kit_review, response: recent, metric: accuracy, ai_score: 4.0)
      orphan = build(:completion_kit_review, response: recent, metric: nil, metric_name: "Orphan",
                                            status: "failed", ai_score: nil)
      orphan.save(validate: false)
      create(:completion_kit_review, response: old, metric: stale, ai_score: 1.0,
                                     created_at: 40.days.ago)

      expect(described_class.worst_metric(since: 7.days.ago)[:name]).to eq("Accuracy")
    end

    it "excludes a dismissed metric while its average holds at or above the baseline" do
      good = create(:completion_kit_metric, name: "Tone")
      bad = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: good, ai_score: 4.0)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: bad, ai_score: 2.0)
      CompletionKit::DashboardDismissal.create!(dismissable: bad, baseline_score: 2.0)

      expect(described_class.worst_metric(since: 7.days.ago)[:name]).to eq("Tone")
    end

    it "resurfaces a dismissed metric that regressed below baseline and clears the stale dismissal" do
      bad = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: bad, ai_score: 1.0)
      dismissal = CompletionKit::DashboardDismissal.create!(dismissable: bad, baseline_score: 3.0)

      result = described_class.worst_metric(since: 7.days.ago)

      expect(result[:name]).to eq("Accuracy")
      expect(CompletionKit::DashboardDismissal.exists?(dismissal.id)).to be(false)
    end

    it "returns nil when every metric is dismissed and holding" do
      metric = create(:completion_kit_metric, name: "Accuracy")
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)
      CompletionKit::DashboardDismissal.create!(dismissable: metric, baseline_score: 3.0)

      expect(described_class.worst_metric(since: 7.days.ago)).to be_nil
    end
  end

  describe ".metric_average" do
    it "returns the rounded window average for a metric" do
      metric = create(:completion_kit_metric)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 2.0)
      create(:completion_kit_review, response: create(:completion_kit_response), metric: metric, ai_score: 3.0)

      expect(described_class.metric_average(metric.id, since: 7.days.ago)).to eq(2.5)
    end

    it "returns nil when the metric has no scored reviews in the window" do
      expect(described_class.metric_average(create(:completion_kit_metric).id, since: 7.days.ago)).to be_nil
    end
  end

  describe ".metric_pass_rate" do
    it "returns the rounded pass rate for a check metric in the window" do
      check = create(:completion_kit_metric, :check)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: true)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: false)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: true)

      expect(described_class.metric_pass_rate(check.id, since: 7.days.ago)).to eq(0.67)
    end

    it "returns nil when there are no resolved checks in the window" do
      check = create(:completion_kit_metric, :check)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: nil, status: "pending")
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: true, created_at: 40.days.ago)

      expect(described_class.metric_pass_rate(check.id, since: 7.days.ago)).to be_nil
    end
  end

  describe ".failing_checks" do
    it "is empty when no checks failed in the window" do
      check = create(:completion_kit_metric, :check)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: true)

      result = described_class.failing_checks(since: 7.days.ago)
      expect(result[:count]).to eq(0)
      expect(result[:items]).to eq([])
    end

    it "collects failed check reviews with their metric name and run, most recent first" do
      check = create(:completion_kit_metric, :check, name: "Valid JSON")
      older = create(:completion_kit_response)
      newer = create(:completion_kit_response)
      create(:completion_kit_review, :check, response: older, metric: check, metric_name: "Valid JSON",
                                             passed: false, updated_at: 3.days.ago)
      create(:completion_kit_review, :check, response: newer, metric: check, metric_name: "Valid JSON",
                                             passed: false, updated_at: 1.hour.ago)

      result = described_class.failing_checks(since: 7.days.ago)

      expect(result[:count]).to eq(2)
      expect(result[:items].first[:metric_name]).to eq("Valid JSON")
      expect(result[:items].first[:run]).to eq(newer.run)
      expect(result[:items].map { |i| i[:response] }).to eq([newer, older])
    end

    it "excludes passing checks, rubric reviews, and out-of-window failures" do
      check = create(:completion_kit_metric, :check)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check, passed: true)
      create(:completion_kit_review, response: create(:completion_kit_response), ai_score: 1.0)
      create(:completion_kit_review, :check, response: create(:completion_kit_response), metric: check,
                                             passed: false, created_at: 40.days.ago)

      expect(described_class.failing_checks(since: 7.days.ago)[:count]).to eq(0)
    end
  end

  describe ".failures" do
    it "is empty when nothing failed in the window" do
      result = described_class.failures(since: 7.days.ago)
      expect(result[:count]).to eq(0)
      expect(result[:items]).to eq([])
    end

    it "aggregates run, generation, and judge failures with cause and run link" do
      run = create(:completion_kit_run, status: "failed", failure_summary: "Worker crashed")
      bad_response = create(:completion_kit_response, :failed)
      good_response = create(:completion_kit_response)
      create(:completion_kit_review, response: good_response, status: "failed",
                                     ai_score: nil, error_class: "CompletionKit::JudgeParseError",
                                     error_provider: "openai")

      result = described_class.failures(since: 7.days.ago)

      expect(result[:count]).to eq(3)
      surfaces = result[:items].map { |i| i[:surface] }
      expect(surfaces).to contain_exactly("run", "generation", "judge")
      run_item = result[:items].find { |i| i[:surface] == "run" }
      expect(run_item[:cause]).to eq("Worker crashed")
      expect(run_item[:run]).to eq(run)
      gen_item = result[:items].find { |i| i[:surface] == "generation" }
      expect(gen_item[:cause]).to eq("Faraday::TimeoutError")
      expect(gen_item[:run]).to eq(bad_response.run)
      judge_item = result[:items].find { |i| i[:surface] == "judge" }
      expect(judge_item[:cause]).to eq("CompletionKit::JudgeParseError")
      expect(judge_item[:run]).to eq(good_response.run)
    end

    it "falls back to default cause text when failure detail is missing" do
      create(:completion_kit_run, status: "failed", failure_summary: nil)
      response = create(:completion_kit_response, status: "failed", error_class: nil)
      create(:completion_kit_review, response: response, status: "failed", ai_score: nil, error_class: nil)

      causes = described_class.failures(since: 7.days.ago)[:items].map { |i| i[:cause] }
      expect(causes).to contain_exactly("Run failed", "Unknown error", "Unknown error")
    end

    it "excludes failures outside the window" do
      create(:completion_kit_run, status: "failed", created_at: 40.days.ago)
      create(:completion_kit_response, :failed, created_at: 40.days.ago)
      expect(described_class.failures(since: 7.days.ago)[:count]).to eq(0)
    end

    it "excludes dismissed failures across all three surfaces" do
      run = create(:completion_kit_run, status: "failed", failure_summary: "crash")
      response = create(:completion_kit_response, :failed)
      review = create(:completion_kit_review, response: create(:completion_kit_response),
                                              status: "failed", ai_score: nil)
      CompletionKit::DashboardDismissal.create!(dismissable: run)
      CompletionKit::DashboardDismissal.create!(dismissable: response)
      CompletionKit::DashboardDismissal.create!(dismissable: review)

      result = described_class.failures(since: 7.days.ago)
      expect(result[:count]).to eq(0)
    end

    it "orders items most recent first" do
      old = create(:completion_kit_run, status: "failed", updated_at: 5.days.ago)
      recent = create(:completion_kit_run, status: "failed", updated_at: 1.hour.ago)

      items = described_class.failures(since: 7.days.ago)[:items]
      expect(items.map { |i| i[:record] }).to eq([recent, old])
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

  describe "with runs_display_scope hiding aged-out runs" do
    around do |example|
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
      example.run
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "omits hidden runs from the activity sparkline" do
      create(:completion_kit_run, created_at: Time.current)
      create(:completion_kit_run, created_at: 90.days.ago)

      expect(described_class.activity(days: 120).sum { |d| d[:count] }).to eq(1)
    end

    it "excludes reviews on hidden runs from metric_average" do
      metric = create(:completion_kit_metric)
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      visible_run = create(:completion_kit_run, created_at: Time.current)
      create(:completion_kit_review, response: create(:completion_kit_response, run: hidden_run), metric: metric, ai_score: 1.0)
      create(:completion_kit_review, response: create(:completion_kit_response, run: visible_run), metric: metric, ai_score: 4.0)

      expect(described_class.metric_average(metric.id, since: 7.days.ago)).to eq(4.0)
    end

    it "excludes reviews on hidden runs from worst_metric" do
      metric = create(:completion_kit_metric, name: "Accuracy")
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      visible_run = create(:completion_kit_run, created_at: Time.current)
      create(:completion_kit_review, response: create(:completion_kit_response, run: hidden_run), metric: metric, ai_score: 1.0)
      visible_response = create(:completion_kit_response, run: visible_run)
      create(:completion_kit_review, response: visible_response, metric: metric, ai_score: 4.0)

      result = described_class.worst_metric(since: 7.days.ago)
      expect(result[:avg]).to eq(4.0)
      expect(result[:response]).to eq(visible_response)
      expect(result[:score]).to eq(4.0)
    end

    it "excludes checks on hidden runs from metric_pass_rate" do
      check = create(:completion_kit_metric, :check)
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      visible_run = create(:completion_kit_run, created_at: Time.current)
      create(:completion_kit_review, :check, response: create(:completion_kit_response, run: hidden_run), metric: check, passed: true)
      create(:completion_kit_review, :check, response: create(:completion_kit_response, run: visible_run), metric: check, passed: false)

      expect(described_class.metric_pass_rate(check.id, since: 7.days.ago)).to eq(0.0)
    end

    it "excludes failed checks on hidden runs from failing_checks" do
      check = create(:completion_kit_metric, :check)
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      visible_run = create(:completion_kit_run, created_at: Time.current)
      create(:completion_kit_review, :check, response: create(:completion_kit_response, run: hidden_run), metric: check, passed: false)
      visible_response = create(:completion_kit_response, run: visible_run)
      create(:completion_kit_review, :check, response: visible_response, metric: check, passed: false)

      result = described_class.failing_checks(since: 7.days.ago)
      expect(result[:count]).to eq(1)
      expect(result[:items].first[:response]).to eq(visible_response)
    end

    it "excludes failures on hidden runs across all three surfaces" do
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      create(:completion_kit_run, status: "failed", created_at: 90.days.ago, failure_summary: "hidden crash")
      create(:completion_kit_response, :failed, run: hidden_run)
      create(:completion_kit_review, response: create(:completion_kit_response, run: hidden_run),
                                     status: "failed", ai_score: nil)

      visible_run = create(:completion_kit_run, created_at: Time.current)
      visible_failed_run = create(:completion_kit_run, status: "failed", created_at: Time.current, failure_summary: "visible crash")
      visible_failed_response = create(:completion_kit_response, :failed, run: visible_run)
      visible_failed_review = create(:completion_kit_review, response: create(:completion_kit_response, run: visible_run),
                                                             status: "failed", ai_score: nil)

      result = described_class.failures(since: 120.days.ago)
      expect(result[:count]).to eq(3)
      expect(result[:items].map { |i| i[:record] }).to contain_exactly(visible_failed_run, visible_failed_response, visible_failed_review)
    end

    it "excludes reviews on hidden runs from prompt_changes averages" do
      v1 = create(:completion_kit_prompt, family_key: "fam", version_number: 1, current: true)
      create(:completion_kit_review, response: create(:completion_kit_response, run: create(:completion_kit_run, prompt: v1)), ai_score: 3.0)

      v2 = create(:completion_kit_prompt, family_key: "fam", version_number: 2, current: false)
      create(:completion_kit_review, response: create(:completion_kit_response, run: create(:completion_kit_run, prompt: v2, created_at: 90.days.ago)), ai_score: 1.0)
      create(:completion_kit_review, response: create(:completion_kit_response, run: create(:completion_kit_run, prompt: v2, created_at: Time.current)), ai_score: 5.0)

      result = described_class.prompt_changes
      expect(result.length).to eq(1)
      expect(result.first).to include(prompt: v2, from_version: 1, to_version: 2, from_score: 3.0, to_score: 5.0, delta: 2.0)
    end
  end
end
