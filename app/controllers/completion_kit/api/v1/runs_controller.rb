module CompletionKit
  module Api
    module V1
      class RunsController < BaseController
        before_action :set_run, only: [:show, :update, :destroy, :generate, :judge]

        def index
          render json: Run.order(created_at: :desc)
        end

        def show
          render json: @run
        end

        def create
          run = Run.new(run_params.except(:metric_ids))
          if run.save
            replace_run_metrics(run, params[:metric_ids])
            render json: run.reload, status: :created
          else
            render json: {errors: run.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @run.update(run_params.except(:metric_ids))
            replace_run_metrics(@run, params[:metric_ids]) if params.key?(:metric_ids)
            render json: @run.reload
          else
            render json: {errors: @run.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @run.destroy!
          head :no_content
        end

        def generate
          GenerateJob.perform_later(@run.id)
          render json: @run.reload, status: :accepted
        end

        def judge
          JudgeJob.perform_later(@run.id)
          render json: @run.reload, status: :accepted
        end

        private

        def set_run
          @run = Run.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def run_params
          params.permit(:name, :prompt_id, :dataset_id, :judge_model, metric_ids: [])
        end

        def replace_run_metrics(run, metric_ids)
          return unless metric_ids
          run.run_metrics.delete_all
          Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
            run.run_metrics.create!(metric_id: metric_id, position: index + 1)
          end
        end
      end
    end
  end
end
