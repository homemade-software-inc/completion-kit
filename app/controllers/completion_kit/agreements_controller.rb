module CompletionKit
  class AgreementsController < ApplicationController
    before_action :ensure_agreement_enabled
    before_action :set_scope

    def create
      created_by = agreement_creator
      existing = Agreement.find_by(
        run_id: @run.id, response_id: @response.id, metric_id: @metric.id, created_by: created_by
      )

      if params[:verdict] == "disagree" && params[:corrected_score].blank?
        render_agreement(agreement: existing, pending_verdict: "disagree")
        return
      end

      agreement = existing || Agreement.new(
        run: @run, response: @response, metric: @metric, created_by: created_by
      )
      agreement.assign_attributes(
        metric_version: MetricVersion.ensure_current_for(@metric),
        verdict: params[:verdict],
        corrected_score: params[:corrected_score].presence,
        note: params[:note].presence
      )

      if agreement.save
        render_agreement(agreement: agreement, just_saved: true)
      else
        render_agreement(
          agreement: existing,
          pending_verdict: params[:verdict],
          error: agreement.errors.full_messages.to_sentence,
          status: :unprocessable_entity
        )
      end
    end

    private

    def render_agreement(agreement:, pending_verdict: nil, error: nil, just_saved: false, status: :ok)
      locals = {
        review: review_for_metric,
        agreement: agreement,
        run: @run,
        response_row: @response,
        metric: @metric,
        pending_verdict: pending_verdict,
        error: error,
        just_saved: just_saved
      }
      render turbo_stream: turbo_stream.replace(
        "agreement_#{@response.id}_#{@metric.id}",
        partial: "completion_kit/agreements/buttons",
        locals: locals
      ), status: status
    end

    def ensure_agreement_enabled
      head :not_found unless CompletionKit.config.judge_agreement_enabled
    end

    def set_scope
      @run = Run.find(params[:run_id])
      @response = @run.responses.find(params[:response_id])
      @metric = Metric.find(params[:metric_id])
    end

    def review_for_metric
      @response.reviews.find_by(metric_id: @metric.id)
    end

    def agreement_creator
      request.env["HTTP_X_REMOTE_USER"].presence || CompletionKit.config.username.presence || "operator"
    end
  end
end
