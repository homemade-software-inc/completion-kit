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
          run = Run.new(run_params)
          if run.save
            render json: run, status: :created
          else
            render json: {errors: run.errors}, status: :unprocessable_entity
          end
        end

        def update
          if @run.update(run_params)
            render json: @run
          else
            render json: {errors: @run.errors}, status: :unprocessable_entity
          end
        end

        def destroy
          @run.destroy!
          head :no_content
        end

        def generate
          if @run.generate_responses!
            render json: @run.reload
          else
            render json: {error: "Generation failed", status: @run.reload.status}, status: :unprocessable_entity
          end
        end

        def judge
          if @run.judge_responses!
            render json: @run.reload
          else
            render json: {error: "Judging failed", status: @run.reload.status}, status: :unprocessable_entity
          end
        end

        private

        def set_run
          @run = Run.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def run_params
          params.permit(:name, :prompt_id, :dataset_id, :judge_model, :criteria_id)
        end
      end
    end
  end
end
