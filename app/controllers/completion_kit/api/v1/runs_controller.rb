module CompletionKit
  module Api
    module V1
      class RunsController < BaseController
        before_action :set_run, only: [:show, :update, :destroy, :generate]

        def index
          render json: Run.order(created_at: :desc)
        end

        def show
          render json: @run
        end

        def create
          run = Run.new(run_params.except(:metric_ids))
          if run.save
            run.replace_metrics!(params[:metric_ids])
            render json: run.reload, status: :created
          else
            render json: {errors: run.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @run.update(run_params.except(:metric_ids))
            @run.replace_metrics!(params[:metric_ids]) if params.key?(:metric_ids)
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
          if @run.start!
            render json: @run.reload, status: :accepted
          else
            render json: { errors: [@run.failure_summary || @run.errors.full_messages.to_sentence] }, status: :unprocessable_entity
          end
        end

        private

        def set_run
          @run = Run.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def run_params
          params.permit(:name, :prompt_id, :dataset_id, :judge_model, :temperature, metric_ids: [])
        end
      end
    end
  end
end
