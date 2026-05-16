require "rails_helper"

RSpec.describe "/completion_kit/calibrations", type: :request do
  let(:run) { create(:completion_kit_run) }
  let(:response_obj) { create(:completion_kit_response, run: run) }
  let(:metric) { create(:completion_kit_metric) }
  let(:anonymous_id) { "test-anonymous-uuid" }

  describe "POST /completion_kit/calibrations" do
    it "creates a calibration with agree verdict" do
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "agree"
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["calibration"]["verdict"]).to eq("agree")
      expect(json["calibration"]["anonymous_id"]).to eq(anonymous_id)
    end

    it "creates a calibration with disagree verdict and corrected score" do
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "disagree",
            corrected_score: 3.5,
            note: "Test note"
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["calibration"]["verdict"]).to eq("disagree")
      expect(json["calibration"]["corrected_score"]).to eq("3.5")
      expect(json["calibration"]["note"]).to eq("Test note")
    end

    it "creates a calibration with borderline verdict" do
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "borderline"
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["calibration"]["verdict"]).to eq("borderline")
    end

    it "updates existing calibration for same anonymous_id" do
      # Create first calibration
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "agree"
          }
        },
        as: :json

      # Update with disagree
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "disagree",
            corrected_score: 2.0
          }
        },
        as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["calibration"]["verdict"]).to eq("disagree")
      expect(json["calibration"]["corrected_score"]).to eq("2.0")

      # Should only have one calibration for this anonymous_id
      calibrations = CompletionKit::Calibration.where(
        run_id: run.id,
        response_id: response_obj.id,
        metric_id: metric.id,
        anonymous_id: anonymous_id
      )
      expect(calibrations.count).to eq(1)
    end

    it "returns unprocessable_entity for invalid verdict" do
      post "/completion_kit/calibrations",
        params: {
          calibration: {
            run_id: run.id,
            response_id: response_obj.id,
            metric_id: metric.id,
            anonymous_id: anonymous_id,
            verdict: "invalid_verdict"
          }
        },
        as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end