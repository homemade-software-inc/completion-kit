module CompletionKit
  module Api
    module V1
      class CriteriaController < BaseController
        before_action :set_criteria, only: [:show, :update, :destroy]

        def index
          render json: Criteria.order(created_at: :desc)
        end

        def show
          render json: @criteria
        end

        def create
          criteria = Criteria.new(criteria_params.except(:metric_ids))
          if criteria.save
            replace_metric_memberships(criteria, params[:metric_ids]) if params.key?(:metric_ids)
            render json: criteria.reload, status: :created
          else
            render json: {errors: criteria.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @criteria.update(criteria_params.except(:metric_ids))
            replace_metric_memberships(@criteria, params[:metric_ids]) if params.key?(:metric_ids)
            render json: @criteria.reload
          else
            render json: {errors: @criteria.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @criteria.destroy!
          head :no_content
        end

        private

        def set_criteria
          @criteria = Criteria.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def criteria_params
          params.permit(:name, :description, metric_ids: [])
        end

        def replace_metric_memberships(criteria, metric_ids)
          return unless metric_ids

          criteria.criteria_memberships.delete_all
          Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
            criteria.criteria_memberships.create!(metric_id: metric_id, position: index + 1)
          end
        end
      end
    end
  end
end
