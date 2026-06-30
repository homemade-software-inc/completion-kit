require "rails_helper"

RSpec.describe CompletionKit::MetricAgreementExamples do
  def disagreement(metric, score: 2.0, judge: 4.0, response: nil, excluded: false)
    response ||= create(:completion_kit_response)
    create(:completion_kit_review, response: response, metric: metric, ai_score: judge, ai_feedback: "judge said")
    create(:completion_kit_agreement,
           metric: metric, response: response, run: response.run,
           verdict: "disagree", corrected_score: score, note: "too high",
           excluded_from_examples: excluded)
  end

  let(:metric) { create(:completion_kit_metric) }

  it "returns corrected cases for the current version with judge and human scores" do
    cal = disagreement(metric)
    examples = described_class.judge_examples_for(metric)
    expect(examples.size).to eq(1)
    expect(examples.first[:id]).to eq(cal.id)
    expect(examples.first[:judge_score]).to eq(4.0)
    expect(examples.first[:human_score]).to eq(2.0)
    expect(examples.first[:human_note]).to eq("too high")
    expect(examples.first[:output]).to eq(cal.response.response_text)
    expect(examples.first[:response_id]).to eq(cal.response_id)
    expect(examples.first[:run_id]).to eq(cal.run_id)
  end

  it "returns an empty array when the metric has no current version" do
    expect(described_class.judge_examples_for(create(:completion_kit_metric))).to eq([])
  end

  it "short-circuits to [] for a check metric before touching the current version" do
    check_metric = create(:completion_kit_metric, :check)
    CompletionKit::MetricVersion.ensure_current_for(check_metric)
    expect(CompletionKit::MetricVersion).not_to receive(:current)
    expect(described_class.judge_examples_for(check_metric)).to eq([])
  end

  it "skips muted cases" do
    disagreement(metric, excluded: true)
    expect(described_class.judge_examples_for(metric)).to eq([])
  end

  it "skips the response being scored" do
    response = create(:completion_kit_response)
    disagreement(metric, response: response)
    expect(described_class.judge_examples_for(metric, exclude_response_id: response.id)).to eq([])
  end

  it "caps the result at the default limit of 5" do
    6.times { disagreement(metric) }
    expect(described_class.judge_examples_for(metric).size).to eq(5)
  end

  it "drops cases that have no judge score" do
    response = create(:completion_kit_response)
    create(:completion_kit_agreement,
           metric: metric, response: response, run: response.run,
           verdict: "disagree", corrected_score: 2.0, note: "no review")
    expect(described_class.judge_examples_for(metric)).to eq([])
  end

  it "does not fall back to corrections from a superseded version" do
    disagreement(metric)
    newer = CompletionKit::MetricVersion.create!(
      metric: metric, instruction: "newer", rubric_bands: metric.rubric_bands,
      state: "draft", source: "edit"
    )
    newer.publish!
    expect(described_class.judge_examples_for(metric)).to eq([])
  end

  describe "with runs_display_scope" do
    it "hides display examples on hidden runs but keeps them for judge seeding" do
      old_run = create(:completion_kit_run, created_at: 90.days.ago)
      response = create(:completion_kit_response, run: old_run)
      disagreement(metric, response: response)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      display = described_class.disagreements_for(metric)
      seeding = described_class.judge_examples_for(metric)

      expect(display.map { |e| e[:run_id] }).not_to include(old_run.id)
      expect(seeding.map { |e| e[:run_id] }).to include(old_run.id)
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end
end
