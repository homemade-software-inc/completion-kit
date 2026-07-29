module CompletionKit
  module Api
    module V1
      class ResponsesController < BaseController
        before_action :set_run
        before_action :set_response, only: [:show]

        def index
          query = ResponseQuery.new(
            @run,
            status: params[:status], min_score: params[:min_score], max_score: params[:max_score],
            sort: params[:sort], fields: params[:fields]
          )
          render json: paginate(query.relation).map { |response| query.serialize(response) }
        end

        def show
          render json: @response
        end

        private

        def set_run
          @run = Run.find(params[:run_id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end

        def set_response
          @response = @run.responses.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          not_found
        end
      end
    end
  end
end
