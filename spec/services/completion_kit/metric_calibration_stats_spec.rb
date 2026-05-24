require "rails_helper"

RSpec.describe CompletionKit::MetricCalibrationStats, type: :service do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }
  let(:judge_version) { CompletionKit::JudgeVersion.ensure_current_for(metric) }

  def add_response(ai_score:)
    response = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: ai_score)
    response
  end

  def add_calibration(response, verdict:, corrected_score: nil, created_by: SecureRandom.uuid)
    create(:completion_kit_calibration,
           run: run, response: response, metric: metric,
           judge_version: judge_version, verdict: verdict,
           corrected_score: corrected_score, created_by: created_by)
  end

  describe ".for" do
    it "returns a counter gate below 10 verdicts" do
      3.times { add_calibration(add_response(ai_score: 4), verdict: "agree") }
      stats = described_class.for(metric)
      expect(stats.gate).to eq(:counter)
      expect(stats.counter_only?).to be(true)
      expect(stats.sample_size).to eq(3)
      expect(stats.short_to_target).to eq(7)
    end

    it "returns a provisional gate at 10..29 verdicts with a Wilson interval" do
      10.times { |i| add_calibration(add_response(ai_score: 4), verdict: (i < 8 ? "agree" : "disagree"), corrected_score: 3) }
      stats = described_class.for(metric)
      expect(stats.gate).to eq(:provisional)
      expect(stats.provisional?).to be(true)
      expect(stats.agreement_point).to eq(0.8)
      expect(stats.agreement_low).to be < 0.8
      expect(stats.agreement_high).to be > 0.8
      expect(stats.margin).to be > 0
      expect(stats.short_to_target).to eq(0)
    end

    it "returns a firm gate at 30+ verdicts" do
      30.times { |i| add_calibration(add_response(ai_score: 4), verdict: (i < 24 ? "agree" : "disagree"), corrected_score: 3) }
      stats = described_class.for(metric)
      expect(stats.gate).to eq(:firm)
      expect(stats.firm?).to be(true)
    end

    it "computes MAE, Pearson, and kappa over agree+disagree pairs, skipping borderlines" do
      5.times { add_calibration(add_response(ai_score: 4), verdict: "agree") }
      5.times { add_calibration(add_response(ai_score: 5), verdict: "disagree", corrected_score: 3) }
      2.times { add_calibration(add_response(ai_score: 4), verdict: "borderline") }

      stats = described_class.for(metric)
      expect(stats.borderline_rate).to be_within(0.001).of(2.0 / 12)
      expect(stats.mae).to be > 0
      expect(stats.pearson).not_to be_nil
      expect(stats.kappa).not_to be_nil
    end

    it "yields nil score-pair stats when there are no scored reviews" do
      response = create(:completion_kit_response, run: run)
      create(:completion_kit_calibration,
             run: run, response: response, metric: metric,
             judge_version: judge_version, verdict: "agree", created_by: "alice")
      stats = described_class.for(metric)
      expect(stats.mae).to be_nil
      expect(stats.pearson).to be_nil
    end

    it "scopes to a specific judge_version when one is passed" do
      newer_version = CompletionKit::JudgeVersion.create!(metric: metric, instruction: "updated", current: false)
      response = add_response(ai_score: 4)
      add_calibration(response, verdict: "agree", created_by: "alice")
      create(:completion_kit_calibration,
             run: run, response: response, metric: metric,
             judge_version: newer_version, verdict: "disagree", corrected_score: 2, created_by: "bob")

      scoped = described_class.for(metric, judge_version: newer_version)
      expect(scoped.sample_size).to eq(1)
      expect(scoped.agree_count).to eq(0)
      expect(scoped.disagree_count).to eq(1)
    end

    it "defaults to the metric's current published judge version, ignoring verdicts on superseded versions" do
      old_version = CompletionKit::JudgeVersion.ensure_current_for(metric)
      r1 = add_response(ai_score: 4)
      create(:completion_kit_calibration,
             run: run, response: r1, metric: metric,
             judge_version: old_version, verdict: "agree", created_by: "alice")
      create(:completion_kit_calibration,
             run: run, response: add_response(ai_score: 3), metric: metric,
             judge_version: old_version, verdict: "agree", created_by: "bob")

      old_version.update!(current: false)
      new_version = CompletionKit::JudgeVersion.create!(
        metric: metric, instruction: "rewritten",
        rubric_bands: metric.rubric_bands, state: "published", current: true
      )
      create(:completion_kit_calibration,
             run: run, response: add_response(ai_score: 5), metric: metric,
             judge_version: new_version, verdict: "agree", created_by: "casey")

      stats = described_class.for(metric)
      expect(stats.sample_size).to eq(1)
      expect(CompletionKit::Calibration.where(metric_id: metric.id).count).to eq(3)
    end

    it "returns lifetime stats across all versions when judge_version: nil is passed explicitly" do
      old_version = CompletionKit::JudgeVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: add_response(ai_score: 4), metric: metric,
             judge_version: old_version, verdict: "agree", created_by: "alice")
      old_version.update!(current: false)
      new_version = CompletionKit::JudgeVersion.create!(
        metric: metric, instruction: "rewritten",
        rubric_bands: metric.rubric_bands, state: "published", current: true
      )
      create(:completion_kit_calibration,
             run: run, response: add_response(ai_score: 5), metric: metric,
             judge_version: new_version, verdict: "agree", created_by: "bob")

      lifetime = described_class.for(metric, judge_version: nil)
      expect(lifetime.sample_size).to eq(2)
    end

    it "yields an empty result when the metric has no current published version" do
      orphan = create(:completion_kit_metric)
      CompletionKit::JudgeVersion.where(metric_id: orphan.id).destroy_all
      stats = described_class.for(orphan)
      expect(stats.sample_size).to eq(0)
      expect(stats.gate).to eq(:counter)
    end

    it "returns zero sample_size with nil interval bounds when no calibrations exist" do
      stats = described_class.for(metric)
      expect(stats.sample_size).to eq(0)
      expect(stats.agreement_point).to be_nil
      expect(stats.margin).to be_nil
      expect(stats.borderline_rate).to be_nil
    end

    it "defensively skips a disagree calibration whose corrected_score was nulled out" do
      response = add_response(ai_score: 4)
      cal = CompletionKit::Calibration.new(
        run: run, response: response, metric: metric,
        judge_version: judge_version, verdict: "disagree",
        corrected_score: nil, created_by: "nulled"
      )
      cal.save(validate: false)
      stats = described_class.for(metric)
      expect(stats.disagree_count).to eq(1)
      expect(stats.mae).to be_nil
    end
  end
end
