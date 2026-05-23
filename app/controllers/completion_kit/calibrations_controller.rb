module CompletionKit
  class CalibrationsController < ApplicationController
    before_action :ensure_calibration_enabled
    before_action :set_scope

    def create
      created_by = calibration_creator
      calibration = Calibration.find_or_initialize_by(
        run_id: @run.id, response_id: @response.id, metric_id: @metric.id, created_by: created_by
      )
      calibration.assign_attributes(
        judge_version: JudgeVersion.ensure_current_for(@metric),
        verdict: params[:verdict],
        corrected_score: params[:corrected_score].presence,
        note: params[:note].presence
      )

      if calibration.save
        render turbo_stream: turbo_stream.replace(
          "calibration_#{@response.id}_#{@metric.id}",
          partial: "completion_kit/calibrations/buttons",
          locals: { review: review_for_metric, calibration: calibration, run: @run, response_row: @response, metric: @metric }
        )
      else
        flash[:alert] = calibration.errors.full_messages.to_sentence
        redirect_to run_response_path(@run, @response)
      end
    end

    private

    def ensure_calibration_enabled
      head :not_found unless CompletionKit.config.judge_calibration_enabled
    end

    def set_scope
      @run = Run.find(params[:run_id])
      @response = @run.responses.find(params[:response_id])
      @metric = Metric.find(params[:metric_id])
    end

    def review_for_metric
      @response.reviews.find_by(metric_id: @metric.id)
    end

    def calibration_creator
      request.env["HTTP_X_REMOTE_USER"].presence || CompletionKit.config.username.presence || "operator"
    end
  end
end
