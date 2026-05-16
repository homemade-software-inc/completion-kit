module CompletionKit
  class CalibrationsController < ApplicationController
    def create
      calibration = Calibration.upsert!(**calibration_params.to_h.symbolize_keys)
      render json: { calibration: calibration.as_json }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def calibration_params
      params.require(:calibration).permit(:run_id, :response_id, :metric_id, :anonymous_id, :verdict, :corrected_score, :note, :judge_version_id)
    end
  end
end
