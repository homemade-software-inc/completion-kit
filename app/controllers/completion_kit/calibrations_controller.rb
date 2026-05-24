module CompletionKit
  class CalibrationsController < ApplicationController
    before_action :ensure_calibration_enabled
    before_action :set_scope

    def create
      created_by = calibration_creator
      existing = Calibration.find_by(
        run_id: @run.id, response_id: @response.id, metric_id: @metric.id, created_by: created_by
      )

      if params[:verdict] == "disagree" && params[:corrected_score].blank?
        render_calibration(calibration: existing, pending_verdict: "disagree")
        return
      end

      calibration = existing || Calibration.new(
        run: @run, response: @response, metric: @metric, created_by: created_by
      )
      calibration.assign_attributes(
        judge_version: JudgeVersion.ensure_current_for(@metric),
        verdict: params[:verdict],
        corrected_score: params[:corrected_score].presence,
        note: params[:note].presence
      )

      if calibration.save
        render_calibration(calibration: calibration, just_saved: true)
      else
        render_calibration(
          calibration: existing,
          pending_verdict: params[:verdict],
          error: calibration.errors.full_messages.to_sentence,
          status: :unprocessable_entity
        )
      end
    end

    private

    def render_calibration(calibration:, pending_verdict: nil, error: nil, just_saved: false, status: :ok)
      locals = {
        review: review_for_metric,
        calibration: calibration,
        run: @run,
        response_row: @response,
        metric: @metric,
        pending_verdict: pending_verdict,
        error: error,
        just_saved: just_saved
      }
      render turbo_stream: turbo_stream.replace(
        "calibration_#{@response.id}_#{@metric.id}",
        partial: "completion_kit/calibrations/buttons",
        locals: locals
      ), status: status
    end

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
