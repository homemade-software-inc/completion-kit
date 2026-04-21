module CompletionKit
  module Api
    module V1
      class MetricGroupsController < BaseController
        before_action :set_metric_group, only: [:show, :update, :destroy]

        def index
          render json: MetricGroup.order(created_at: :desc)
        end

        def show
          render json: @metric_group
        end

        def create
          metric_group = MetricGroup.new(metric_group_params.except(:metric_ids))
          if metric_group.save
            metric_group.replace_metrics!(params[:metric_ids]) if params.key?(:metric_ids)
            render json: metric_group.reload, status: :created
          else
            render json: {errors: metric_group.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @metric_group.update(metric_group_params.except(:metric_ids))
            @metric_group.replace_metrics!(params[:metric_ids]) if params.key?(:metric_ids)
            render json: @metric_group.reload
          else
            render json: {errors: @metric_group.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @metric_group.destroy!
          head :no_content
        end

        private

        def set_metric_group
          @metric_group = MetricGroup.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def metric_group_params
          params.permit(:name, :description, metric_ids: [])
        end
      end
    end
  end
end
