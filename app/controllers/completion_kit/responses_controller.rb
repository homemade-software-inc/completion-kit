module CompletionKit
  class ResponsesController < ApplicationController
    include CompletionKit::ResponseOrdering
    before_action :set_run
    before_action :set_response

    def show
      @sort = params[:sort]
      ordered_ids = ordered_response_ids
      current_index = ordered_ids.index(@response.id)
      @response_number = current_index + 1
      @reviews = @response.reviews.includes(:metric, :metric_version)
      @prev_response = current_index > 0 ? ordered_ids[current_index - 1] : nil
      @next_response = ordered_ids[current_index + 1]
    end

    private

    def set_run
      @run = Run.find(params[:run_id])
    end

    def set_response
      @response = @run.responses.find(params[:id])
    end

    def ordered_response_ids
      ordered_responses_relation(@run, @sort).pluck(:id)
    end
  end
end
