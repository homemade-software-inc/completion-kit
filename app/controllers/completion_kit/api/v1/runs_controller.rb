module CompletionKit
  module Api
    module V1
      class RunsController < BaseController
        before_action :set_run, only: [:show, :update, :destroy, :generate, :retry_failures]

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

        def retry_failures
          scope = @run.responses.where(status: "failed")
          scope = scope.where(id: params[:only]) if params[:only].present?

          ActiveRecord::Base.transaction do
            failed_response_ids = scope.pluck(:id)
            CompletionKit::Review.where(response_id: failed_response_ids, status: "failed").update_all(
              status: "pending", attempts: 0,
              error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
              ai_score: nil, ai_feedback: nil
            )
            scope.update_all(
              status: "pending", attempts: 0,
              error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
              response_text: nil
            )
            @run.update!(status: "running")
            failed_response_ids.each { |rid| CompletionKit::GenerateRowJob.perform_later(@run.id, rid) }
          end

          render json: @run.reload, status: :accepted
        end

        private

        def set_run
          @run = Run.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def run_params
          params.permit(:name, :prompt_id, :dataset_id, :judge_model, :temperature,
            metric_ids: [], tag_names: [])
        end
      end
    end
  end
end
