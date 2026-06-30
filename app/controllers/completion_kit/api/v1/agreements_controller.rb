module CompletionKit
  module Api
    module V1
      class AgreementsController < BaseController
        before_action :ensure_agreement_enabled
        before_action :set_nested_scope, only: [:create]
        before_action :reject_check_metric, only: [:create]
        before_action :load_agreement, only: [:destroy]

        def index
          scope = Agreement.all
          scope = scope.where(run_id: params[:run_id]) if params[:run_id].present?
          scope = scope.where(response_id: params[:response_id]) if params[:response_id].present?
          scope = scope.where(metric_id: params[:metric_id]) if params[:metric_id].present?
          scope = scope.where(metric_version_id: params[:metric_version_id]) if params[:metric_version_id].present?
          scope = scope.where(created_by: params[:created_by]) if params[:created_by].present?
          scope = scope.where(verdict: params[:verdict]) if params[:verdict].present?
          render json: paginate(scope.order(:created_at))
        end

        def create
          agreement = scope_agreements.find_or_initialize_by(created_by: created_by_param)
          agreement.assign_attributes(
            run: @run,
            response: @response,
            metric: @metric,
            metric_version: MetricVersion.ensure_current_for(@metric),
            **agreement_params
          )

          if agreement.save
            render json: agreement, status: agreement.previously_new_record? ? :created : :ok
          else
            render_validation_errors(agreement)
          end
        end

        def destroy
          @agreement.destroy!
          head :no_content
        end

        private

        def ensure_agreement_enabled
          render_error("Agreement disabled", status: :not_found) unless CompletionKit.config.judge_agreement_enabled
        end

        def set_nested_scope
          @run = Run.find(params[:run_id])
          @response = @run.responses.find(params[:response_id])
          @metric = Metric.find(params[:metric_id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def reject_check_metric
          render_error("Checks have nothing to calibrate", status: :unprocessable_entity) if @metric.check?
        end

        def load_agreement
          @agreement = Agreement.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def scope_agreements
          Agreement.where(run_id: @run.id, response_id: @response.id, metric_id: @metric.id)
        end

        def agreement_params
          params.permit(:verdict, :corrected_score, :note).to_h.symbolize_keys
        end

        def created_by_param
          params[:created_by].presence || "api"
        end
      end
    end
  end
end
