require "rails_helper"

RSpec.describe CompletionKit::MetricImprovementValidator do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }

  def reviewed(verdict:, ai:, corrected: nil)
    response = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: response, metric: metric, ai_score: ai)
    create(:completion_kit_calibration,
           metric: metric, response: response, run: run,
           metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
           verdict: verdict, corrected_score: corrected, created_by: SecureRandom.uuid)
    response
  end

  it "tallies fixes, keeps, breaks, still-off and before/after against an injected scorer" do
    fix = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    still = reviewed(verdict: "disagree", ai: 5.0, corrected: 1.0)
    keep = reviewed(verdict: "agree", ai: 3.0)
    breaks = reviewed(verdict: "agree", ai: 4.0)
    scores = { fix.id => 2, still.id => 4, keep.id => 3, breaks.id => 1 }

    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(resp, _cand) { scores[resp.id] }).call

    expect(summary["total"]).to eq(4)
    expect(summary["fixes"]).to eq(1)
    expect(summary["still_off"]).to eq(1)
    expect(summary["keeps"]).to eq(1)
    expect(summary["breaks"]).to eq(1)
    expect(summary["before"]).to eq(2)
    expect(summary["after"]).to eq(2)
    expect(summary["rows"].size).to eq(4)
  end

  it "excludes borderlines and caps the answer key at 30 most recent" do
    reviewed(verdict: "borderline", ai: 3.0)
    35.times { reviewed(verdict: "agree", ai: 3.0) }
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 3 }).call
    expect(summary["total"]).to eq(30)
    expect(summary["capped"]).to eq(true)
  end

  it "skips a case whose re-score raises and reports tested count" do
    a = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    scorer = ->(resp, _c) { resp.id == a.id ? (raise "boom") : 2 }
    summary = described_class.new(metric, candidate, scorer: scorer).call
    expect(summary["tested"]).to eq(1)
    expect(summary["fixes"]).to eq(1)
  end

  it "only considers reviews on the metric's current version" do
    reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    new_version = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
    new_version.publish!
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 2 }).call
    expect(summary["total"]).to eq(0)
  end

  it "returns an empty summary when the metric has no current version" do
    candidate = CompletionKit::MetricVersion.new(metric: metric, instruction: "c", rubric_bands: [], state: "draft", source: "suggestion")
    summary = described_class.new(metric, candidate, scorer: ->(_r, _c) { 3 }).call
    expect(summary["total"]).to eq(0)
  end

  it "re-scores via JudgeService when no scorer is injected" do
    resp = reviewed(verdict: "disagree", ai: 4.0, corrected: 2.0)
    candidate = CompletionKit::MetricVersion.create!(metric: metric, instruction: "c", rubric_bands: metric.rubric_bands || [], state: "draft", source: "suggestion")
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    judge = instance_double(CompletionKit::JudgeService, evaluate: { score: 2, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
    summary = described_class.new(metric, candidate).call
    expect(summary["fixes"]).to eq(1)
  end
end
