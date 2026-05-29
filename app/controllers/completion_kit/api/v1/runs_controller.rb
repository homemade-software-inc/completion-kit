module CompletionKit
  module Api
    module V1
      class RunsController < BaseController
        before_action :set_run, only: [:show, :update, :destroy, :generate, :retry_failures, :rerun, :regrade, :compare]

        def index
          scope = Run.includes(:tags)
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(prompt_id: params[:prompt_id]) if params[:prompt_id].present?
          scope = scope.where(dataset_id: params[:dataset_id]) if params[:dataset_id].present?
          scope = filter_by_tags(scope)
          render json: paginate(scope.order(created_at: :desc))
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
            render_validation_errors(run)
          end
        end

        def update
          if @run.update(run_params.except(:metric_ids))
            @run.replace_metrics!(params[:metric_ids]) if params.key?(:metric_ids)
            render json: @run.reload
          else
            render_validation_errors(@run)
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
            render_error(@run.failure_summary || @run.errors.full_messages.to_sentence, status: :unprocessable_entity)
          end
        end

        def retry_failures
          if @run.stale_review_summary.any?
            return render_error("Judge has changed since this run executed. Retry would mix versions in the same run; use POST /api/v1/runs/:id/rerun instead.", status: :conflict)
          end

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

        def rerun
          new_run = Run.create!(
            prompt_id: @run.prompt_id,
            dataset_id: @run.dataset_id,
            judge_model: @run.judge_model,
            temperature: @run.temperature,
            output_column: @run.output_column,
            tag_names: @run.tag_names,
            status: "pending"
          )
          new_run.replace_metrics!(@run.metric_ids)
          if new_run.start!
            render json: new_run.reload, status: :accepted
          else
            render_error(new_run.failure_summary || "Could not start the new run.", status: :unprocessable_entity)
          end
        end

        def regrade
          if @run.regrade!
            render json: @run.reload, status: :accepted
          else
            render_error("Nothing to re-grade. The run has no succeeded responses or no metrics attached.", status: :unprocessable_entity)
          end
        end

        def compare
          other = Run.find(params[:with])
          comparison = build_run_comparison(@run, other)
          render json: { left_run_id: @run.id, right_run_id: other.id, metric_ids: comparison[:metric_ids], rows: comparison[:rows] }
        rescue ActiveRecord::RecordNotFound
          render_error("Other run not found. Pass ?with=<run_id>.", status: :not_found)
        end

        private

        def build_run_comparison(left, right)
          left_responses = left.responses.includes(:reviews).order(:row_index, :id)
          right_responses = right.responses.includes(:reviews).order(:row_index, :id)
          right_by_input = right_responses.each_with_object({}) { |r, h| h[r.input_data.to_s] ||= r }
          all_reviews = left_responses.flat_map(&:reviews) + right_responses.flat_map(&:reviews)
          metric_ids = all_reviews.map(&:metric_id).compact.uniq
          metric_versions = MetricVersion.where(id: all_reviews.map(&:metric_version_id).compact.uniq).index_by(&:id)

          rows = left_responses.map do |lr|
            rr = right_by_input[lr.input_data.to_s]
            {
              left_response_id: lr.id,
              right_response_id: rr&.id,
              row_index: lr.row_index,
              per_metric: metric_ids.map do |mid|
                l_review = lr.reviews.find { |r| r.metric_id == mid }
                r_review = rr && rr.reviews.find { |r| r.metric_id == mid }
                next nil if l_review.nil? && r_review.nil?
                anchor = l_review || r_review
                {
                  metric_id: mid,
                  metric_name: anchor.metric_name,
                  left_score: l_review ? l_review.ai_score : nil,
                  right_score: r_review ? r_review.ai_score : nil,
                  left_metric_version_id: l_review&.metric_version_id,
                  right_metric_version_id: r_review&.metric_version_id,
                  delta: (l_review&.ai_score && r_review&.ai_score) ? (r_review.ai_score.to_f - l_review.ai_score.to_f).round(2) : nil
                }
              end.compact
            }
          end
          { rows: rows, metric_ids: metric_ids }
        end

        def set_run
          @run = Run.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def run_params
          params.permit(:name, :prompt_id, :dataset_id, :judge_model, :temperature, :output_column,
            metric_ids: [], tag_names: [])
        end
      end
    end
  end
end
