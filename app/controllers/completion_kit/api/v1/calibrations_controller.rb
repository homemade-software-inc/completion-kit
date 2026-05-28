module CompletionKit
  module Api
    module V1
      class CalibrationsController < BaseController
        before_action :ensure_calibration_enabled
        before_action :set_scope

        def index
          render json: scope_calibrations
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

        private

        def ensure_calibration_enabled
          render(json: { error: "Calibration disabled" }, status: :not_found) unless CompletionKit.config.judge_calibration_enabled
        end

        def set_scope
          @run = Run.find(params[:run_id])
          @response = @run.responses.find(params[:response_id])
          @metric = Metric.find(params[:metric_id])
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
