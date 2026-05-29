module CompletionKit
  module Api
    module V1
      class CalibrationsController < BaseController
        before_action :ensure_calibration_enabled
        before_action :set_nested_scope, only: [:create]
        before_action :load_calibration, only: [:destroy]

        def index
          scope = Calibration.all
          scope = scope.where(run_id: params[:run_id]) if params[:run_id].present?
          scope = scope.where(response_id: params[:response_id]) if params[:response_id].present?
          scope = scope.where(metric_id: params[:metric_id]) if params[:metric_id].present?
          scope = scope.where(metric_version_id: params[:metric_version_id]) if params[:metric_version_id].present?
          scope = scope.where(created_by: params[:created_by]) if params[:created_by].present?
          scope = scope.where(verdict: params[:verdict]) if params[:verdict].present?
          render json: paginate(scope.order(:created_at))
        end

        def create
          calibration = scope_calibrations.find_or_initialize_by(created_by: created_by_param)
          calibration.assign_attributes(
            run: @run,
            response: @response,
            metric: @metric,
            metric_version: MetricVersion.ensure_current_for(@metric),
            **calibration_params
          )

          if calibration.save
            render json: calibration, status: calibration.previously_new_record? ? :created : :ok
          else
            render json: { errors: calibration.errors }, status: :unprocessable_entity
          end
        end

        def destroy
          @calibration.destroy!
          head :no_content
        end

        private

        def ensure_calibration_enabled
          render(json: { error: "Calibration disabled" }, status: :not_found) unless CompletionKit.config.judge_calibration_enabled
        end

        def set_nested_scope
          @run = Run.find(params[:run_id])
          @response = @run.responses.find(params[:response_id])
          @metric = Metric.find(params[:metric_id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def load_calibration
          @calibration = Calibration.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def scope_calibrations
          Calibration.where(run_id: @run.id, response_id: @response.id, metric_id: @metric.id)
        end

        def calibration_params
          params.permit(:verdict, :corrected_score, :note).to_h.symbolize_keys
        end

        def created_by_param
          params[:created_by].presence || "api"
        end
      end
    end
  end
end
