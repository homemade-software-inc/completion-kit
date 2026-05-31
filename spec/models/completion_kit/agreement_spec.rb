require "rails_helper"

RSpec.describe CompletionKit::Agreement, type: :model do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }
  let(:response) { create(:completion_kit_response, run: run) }
  let(:metric_version) { CompletionKit::MetricVersion.ensure_current_for(metric) }

  def build_agreement(attrs = {})
    build(:completion_kit_agreement,
          run: run, response: response, metric: metric, metric_version: metric_version, **attrs)
  end

  describe "validations" do
    it "is valid with an agree verdict and no corrected score" do
      expect(build_agreement(verdict: "agree")).to be_valid
    end

    it "is valid with a disagree verdict + corrected score in range" do
      expect(build_agreement(verdict: "disagree", corrected_score: 3.0)).to be_valid
    end

    it "is invalid when verdict is unknown" do
      cal = build_agreement(verdict: "shrug")
      expect(cal).not_to be_valid
      expect(cal.errors[:verdict]).to be_present
    end

    it "is invalid when disagreeing without a corrected score" do
      cal = build_agreement(verdict: "disagree", corrected_score: nil)
      expect(cal).not_to be_valid
      expect(cal.errors[:corrected_score]).to include("must be set when disagreeing with the judge")
    end

    it "is invalid when corrected score is outside 1..5" do
      below = build_agreement(verdict: "disagree", corrected_score: 0.5)
      above = build_agreement(verdict: "disagree", corrected_score: 5.5)
      expect(below).not_to be_valid
      expect(above).not_to be_valid
      expect(below.errors[:corrected_score]).to include("must be between 1 and 5")
    end

    it "is unique on (response, metric, created_by)" do
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric,
             metric_version: metric_version, created_by: "alice")
      duplicate = build(:completion_kit_agreement,
                        run: run, response: response, metric: metric,
                        metric_version: metric_version, created_by: "alice")
      expect(duplicate).not_to be_valid
    end

    it "allows the same response+metric for a different user" do
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric,
             metric_version: metric_version, created_by: "alice")
      other = build(:completion_kit_agreement,
                    run: run, response: response, metric: metric,
                    metric_version: metric_version, created_by: "bob")
      expect(other).to be_valid
    end
  end

  describe "scopes" do
    it "scopes by run and metric" do
      cal = create(:completion_kit_agreement,
                   run: run, response: response, metric: metric, metric_version: metric_version)
      expect(described_class.for_run(run.id)).to include(cal)
      expect(described_class.for_metric(metric.id)).to include(cal)
    end
  end

  it "defaults excluded_from_examples to false" do
    agreement = create(:completion_kit_agreement)
    expect(agreement.excluded_from_examples).to eq(false)
  end

  describe "#as_json" do
    it "exposes the structured payload" do
      cal = create(:completion_kit_agreement,
                   run: run, response: response, metric: metric,
                   metric_version: metric_version,
                   verdict: "borderline", note: "rubric ambiguous")
      payload = cal.as_json
      expect(payload).to include(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        metric_version_id: metric_version.id,
        verdict: "borderline",
        note: "rubric ambiguous"
      )
    end
  end
end
