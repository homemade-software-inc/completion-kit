require "rails_helper"

RSpec.describe CompletionKit::Calibration, type: :model do
  let(:run) { create(:completion_kit_run) }
  let(:response) { create(:completion_kit_response, run: run) }
  let(:metric) { create(:completion_kit_metric) }
  let(:anonymous_id) { "test-anonymous-uuid-123" }

  describe "validations" do
    it "validates verdict is in allowed list" do
      calibration = CompletionKit::Calibration.new(
        run: run,
        response: response,
        metric: metric,
        anonymous_id: anonymous_id,
        verdict: "invalid"
      )
      expect(calibration).not_to be_valid
      expect(calibration.errors[:verdict]).to include("is not included in the list")
    end

    %w[agree disagree borderline].each do |verdict|
      it "allows verdict: #{verdict}" do
        calibration = CompletionKit::Calibration.new(
          run: run,
          response: response,
          metric: metric,
          anonymous_id: anonymous_id,
          verdict: verdict
        )
        expect(calibration).to be_valid
      end
    end

    it "validates corrected_score is between 1 and 5" do
      calibration = CompletionKit::Calibration.new(
        run: run,
        response: response,
        metric: metric,
        anonymous_id: anonymous_id,
        verdict: "disagree",
        corrected_score: 6
      )
      expect(calibration).not_to be_valid
      expect(calibration.errors[:corrected_score]).to include("must be less than or equal to 5")
    end
  end

  describe ".upsert!" do
    it "creates a new calibration" do
      calibration = CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "agree"
      )
      expect(calibration).to be_persisted
      expect(calibration.verdict).to eq("agree")
    end

    it "updates existing calibration with same keys" do
      original = CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "agree"
      )

      updated = CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "disagree",
        corrected_score: 3.5,
        note: "Test note"
      )

      expect(original.id).to eq(updated.id)
      expect(updated.verdict).to eq("disagree")
      expect(updated.corrected_score).to eq(3.5)
      expect(updated.note).to eq("Test note")
    end

    it "allows nil corrected_score" do
      calibration = CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "borderline"
      )
      expect(calibration.corrected_score).to be_nil
    end

    it "allows updating own verdict" do
      CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "agree"
      )
      updated = CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "disagree"
      )
      expect(updated.verdict).to eq("disagree")
    end
  end

  describe "scopes" do
    let!(:calibration) do
      CompletionKit::Calibration.upsert!(
        run_id: run.id,
        response_id: response.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id,
        verdict: "agree"
      )
    end

    it ".for_response filters by response" do
      other_response = create(:completion_kit_response, run: run)
      expect(CompletionKit::Calibration.for_response(response)).to include(calibration)
      expect(CompletionKit::Calibration.for_response(other_response)).to be_empty
    end

    it ".for_metric filters by metric" do
      other_metric = create(:completion_kit_metric, name: "Other Metric")
      expect(CompletionKit::Calibration.for_metric(metric)).to include(calibration)
      expect(CompletionKit::Calibration.for_metric(other_metric)).to be_empty
    end

    it ".by_anonymous_id filters by anonymous_id" do
      expect(CompletionKit::Calibration.by_anonymous_id(anonymous_id)).to include(calibration)
      expect(CompletionKit::Calibration.by_anonymous_id("other-uuid")).to be_empty
    end
  end
end