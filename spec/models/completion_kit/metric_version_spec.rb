require "rails_helper"

RSpec.describe CompletionKit::MetricVersion, type: :model do
  describe "Review#stale_against_current_judge?" do
    let(:metric) { create(:completion_kit_metric) }
    let(:response_row) { create(:completion_kit_response) }

    it "returns false when the review carries no metric_version_id" do
      review = build(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version: nil)
      review.save(validate: false)
      expect(review.stale_against_current_judge?).to be(false)
    end

    it "returns true when the review's metric_version is not the metric's current version" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands, state: "draft", source: "edit")
      v2.publish!
      expect(review.stale_against_current_judge?).to be(true)
    end

    it "returns false when the review's metric_version matches the metric's current version" do
      current = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: current.id)
      expect(review.stale_against_current_judge?).to be(false)
    end

    it "returns false when there is no current version recorded for the metric" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      review = create(:completion_kit_review, response: response_row, metric: metric, metric_name: metric.name, ai_score: 4, metric_version_id: v1.id)
      CompletionKit::MetricVersion.where(metric_id: metric.id).destroy_all
      expect(review.stale_against_current_judge?).to be(false)
    end
  end

  it "honors an explicit version_number on create instead of auto-incrementing" do
    metric = create(:completion_kit_metric)
    CompletionKit::MetricVersion.create!(metric: metric, instruction: "a", state: "published", current: true)
    v = CompletionKit::MetricVersion.create!(metric: metric, instruction: "b", state: "draft", current: false, version_number: 99)
    expect(v.version_number).to eq(99)
  end

  describe "associations" do
    it "belongs to a metric and has many calibrations" do
      jv = create(:completion_kit_metric_version)
      expect(jv.metric).to be_present
      expect(jv.calibrations).to eq([])
    end
  end

  describe ".ensure_current_for" do
    it "creates a current version when none exists, copying instruction and rubric bands" do
      metric = create(:completion_kit_metric, instruction: "Be helpful")
      jv = described_class.ensure_current_for(metric)
      expect(jv).to be_persisted
      expect(jv.current).to eq(true)
      expect(jv.instruction).to eq("Be helpful")
      expect(jv.rubric_bands).to eq(metric.rubric_bands)
    end

    it "returns the existing current version when one already exists" do
      metric = create(:completion_kit_metric)
      first = described_class.ensure_current_for(metric)
      second = described_class.ensure_current_for(metric)
      expect(second.id).to eq(first.id)
    end
  end

  describe "#as_json" do
    it "returns the structured payload" do
      jv = create(:completion_kit_metric_version, instruction: "Be precise")
      payload = jv.as_json
      expect(payload).to include(
        id: jv.id,
        metric_id: jv.metric_id,
        instruction: "Be precise",
        current: true
      )
      expect(payload[:rubric_bands]).to be_an(Array)
      expect(payload[:created_at]).to be_present
    end
  end

  describe "state predicates" do
    it "exposes draft? and published?" do
      published = create(:completion_kit_metric_version, state: "published")
      draft = create(:completion_kit_metric_version, state: "draft", current: false)
      expect(published.published?).to be(true)
      expect(published.draft?).to be(false)
      expect(draft.draft?).to be(true)
      expect(draft.published?).to be(false)
    end
  end

  describe ".current scope" do
    it "returns only versions flagged as current" do
      metric = create(:completion_kit_metric)
      current = create(:completion_kit_metric_version, metric: metric, current: true)
      create(:completion_kit_metric_version, metric: metric, current: false)
      expect(described_class.current.where(metric: metric)).to contain_exactly(current)
    end
  end

  describe "#change_summary_against" do
    def version(instruction:, bands:)
      metric = create(:completion_kit_metric)
      CompletionKit::MetricVersion.create!(metric: metric, instruction: instruction, rubric_bands: bands, state: "draft", source: "edit", current: false)
    end

    it "returns nil when there is no predecessor" do
      expect(version(instruction: "x", bands: []).change_summary_against(nil)).to be_nil
    end

    it "returns nil when nothing changed" do
      bands = [{ "stars" => 5, "description" => "great" }]
      prev = version(instruction: "same", bands: bands)
      curr = version(instruction: "same", bands: bands)
      expect(curr.change_summary_against(prev)).to be_nil
    end

    it "flags a tiny instruction tweak as trivial" do
      prev = version(instruction: "Be fair here", bands: [])
      curr = version(instruction: "Be fair now", bands: [])
      s = curr.change_summary_against(prev)
      expect(s[:magnitude]).to eq(:trivial)
      expect(s[:label]).to eq("Trivial instruction changes")
    end

    it "flags a single rubric band edit as minor" do
      prev = version(instruction: "same", bands: [{ "stars" => 5, "description" => "great" }])
      curr = version(instruction: "same", bands: [{ "stars" => 5, "description" => "excellent and complete" }])
      s = curr.change_summary_against(prev)
      expect(s[:magnitude]).to eq(:minor)
      expect(s[:label]).to eq("Minor rubric changes")
    end

    it "flags instruction plus rubric changes as major" do
      prev = version(instruction: "Old wording entirely", bands: [{ "stars" => 5, "description" => "great" }])
      curr = version(instruction: "Brand new instruction text", bands: [{ "stars" => 5, "description" => "totally different bar" }])
      s = curr.change_summary_against(prev)
      expect(s[:magnitude]).to eq(:major)
      expect(s[:label]).to eq("Major instruction and rubric changes")
    end

    it "flags two or more rubric band edits as major" do
      prev = version(instruction: "same", bands: [{ "stars" => 5, "description" => "a" }, { "stars" => 4, "description" => "b" }])
      curr = version(instruction: "same", bands: [{ "stars" => 5, "description" => "x" }, { "stars" => 4, "description" => "y" }])
      s = curr.change_summary_against(prev)
      expect(s[:magnitude]).to eq(:major)
      expect(s[:label]).to eq("Major rubric changes")
    end
  end

  describe "validation_summary" do
    it "stores and reads a validation_summary hash" do
      v = create(:completion_kit_metric_version, validation_summary: { "before" => 1, "after" => 4 })
      expect(v.reload.validation_summary).to eq({ "before" => 1, "after" => 4 })
    end

    it "defaults validation_summary to nil" do
      expect(create(:completion_kit_metric_version).validation_summary).to be_nil
    end
  end
end
