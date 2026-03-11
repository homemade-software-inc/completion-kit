module CompletionKit
  class ResponsesController < ApplicationController
    before_action :set_run
    before_action :set_response

    def show
      @reviews = @response.reviews.includes(:metric)
    end

    private

    def set_run
      @run = Run.find(params[:run_id])
    end

    def set_response
      @response = @run.responses.find(params[:id])
    end
  end
end
