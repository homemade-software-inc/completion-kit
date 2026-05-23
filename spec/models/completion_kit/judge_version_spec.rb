require "rails_helper"

RSpec.describe CompletionKit::JudgeVersion, type: :model do
  describe "associations" do
    it "belongs to a metric and has many calibrations" do
      jv = create(:completion_kit_judge_version)
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
      jv = create(:completion_kit_judge_version, instruction: "Be precise")
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

  describe ".current scope" do
    it "returns only versions flagged as current" do
      metric = create(:completion_kit_metric)
      current = create(:completion_kit_judge_version, metric: metric, current: true)
      create(:completion_kit_judge_version, metric: metric, current: false)
      expect(described_class.current.where(metric: metric)).to contain_exactly(current)
    end
  end
end
