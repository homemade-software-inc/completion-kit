module CompletionKit
  module Api
    module V1
      class MetricsController < BaseController
        before_action :set_metric, only: [:show, :update, :destroy, :suggest_variants]

        def index
          scope = Metric.includes(:tags)
          scope = filter_by_tags(scope)
          render json: paginate(scope.order(created_at: :desc))
        end

        def show
          render json: @metric
        end

        def create
          metric = Metric.new(metric_params)
          if metric.save
            render json: metric, status: :created
          else
            render_validation_errors(metric)
          end
        end

        def update
          if @metric.update(metric_params)
            render json: @metric
          else
            render_validation_errors(@metric)
          end
        end

        def destroy
          @metric.destroy!
          head :no_content
        end

        def suggest_variants
          disagreement_count = Agreement.where(metric_id: @metric.id, verdict: "disagree").count
          if disagreement_count.zero?
            render_error("Mark at least one case as Disagree before asking the model to suggest a change.", status: :unprocessable_entity)
            return
          end

          MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").destroy_all
          generator = MetricVariantGenerator.new(@metric, count: params[:count].to_i, model: params[:model])
          variants = generator.call
          if variants.empty?
            render_error("The model returned no usable variants. Try again with a different model.", status: :unprocessable_entity)
            return
          end
          versions = generator.persist!(variants)
          render json: versions, status: :created
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
