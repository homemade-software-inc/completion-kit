module CompletionKit
  module Api
    module V1
      class MetricVersionsController < BaseController
        before_action :set_metric
        before_action :set_version, only: [:show, :publish, :destroy]

        def index
          render json: paginate(@metric.metric_versions.order(version_number: :desc))
        end

        def show
          render json: @version
        end

        def publish
          if @version.published? && !@version.current?
            audit = @version.revert!
            render json: audit
          else
            @version.publish!
            render json: @version.reload
          end
        end

        def destroy
          if @version.published?
            render_error("Cannot dismiss a published version. Publish a different version as current instead.", status: :conflict)
            return
          end
          @version.destroy!
          head :no_content
        end

        private

        def set_metric
          @metric = Metric.find(params[:metric_id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def set_version
          @version = @metric.metric_versions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end
      end
    end
  end
end
