module CompletionKit
  module Api
    module V1
      class MetricsController < BaseController
        before_action :set_metric, only: [:show, :update, :destroy, :suggest_variants, :add_few_shot, :remove_few_shot]

        def index
          render json: Metric.includes(:tags).order(created_at: :desc)
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

        def suggest_variants
          disagreement_count = Calibration.where(metric_id: @metric.id, verdict: "disagree").count
          if disagreement_count.zero?
            render json: { error: "Mark at least one case as Disagree before asking the model to suggest a change." }, status: :unprocessable_entity
            return
          end

          MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").destroy_all
          generator = MetricVariantGenerator.new(@metric, count: params[:count].to_i, model: params[:model])
          variants = generator.call
          if variants.empty?
            render json: { error: "The model returned no usable variants. Try again with a different model." }, status: :unprocessable_entity
            return
          end
          versions = generator.persist!(variants)
          render json: versions, status: :created
        end

        def add_few_shot
          calibration = Calibration.where(metric_id: @metric.id, verdict: "disagree").find(params[:calibration_id])
          review = calibration.response.reviews.find_by(metric_id: @metric.id)
          examples = Array(@metric.few_shot_examples)
          examples << {
            "input" => calibration.response.input_data.to_s.truncate(2000),
            "response" => calibration.response.response_text.to_s.truncate(2000),
            "judge_score" => review&.ai_score&.to_f,
            "judge_feedback" => review&.ai_feedback.to_s.truncate(1000),
            "human_score" => calibration.corrected_score&.to_f,
            "human_note" => calibration.note.to_s.truncate(1000),
            "calibration_id" => calibration.id,
            "added_at" => Time.current.utc.iso8601
          }
          @metric.update!(few_shot_examples: examples)
          render json: @metric.reload
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Calibration not found or not a disagree on this metric." }, status: :not_found
        end

        def remove_few_shot
          cal_id = params[:calibration_id].to_i
          remaining = Array(@metric.few_shot_examples).reject { |fs| fs["calibration_id"].to_i == cal_id }
          @metric.update!(few_shot_examples: remaining)
          render json: @metric.reload
        end

        private

        def set_metric
          @metric = Metric.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def metric_params
          params.permit(:name, :instruction,
            rubric_bands: [:stars, :description], tag_names: [])
        end
      end
    end
  end
end
