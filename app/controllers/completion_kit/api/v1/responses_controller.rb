module CompletionKit
  module Api
    module V1
      class ResponsesController < BaseController
        before_action :set_run
        before_action :set_response, only: [:show]

        def index
          render json: @run.responses.includes(:reviews)
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
