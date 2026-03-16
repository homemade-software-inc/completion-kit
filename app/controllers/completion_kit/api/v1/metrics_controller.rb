module CompletionKit
  module Api
    module V1
      class MetricsController < BaseController
        before_action :set_metric, only: [:show, :update, :destroy]

        def index
          render json: Metric.order(created_at: :desc)
        end

        def show
          render json: @metric
        end

        def create
          metric = Metric.new(metric_params)
          if metric.save
            render json: metric, status: :created
          else
            render json: {errors: metric.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @metric.update(metric_params)
            render json: @metric
          else
            render json: {errors: @metric.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @metric.destroy!
          head :no_content
        end

        private

        def set_metric
          @metric = Metric.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def metric_params
          params.permit(:name, :criteria, evaluation_steps: [], rubric_bands: [:stars, :description])
        end
      end
    end
  end
end
