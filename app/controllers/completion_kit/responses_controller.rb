module CompletionKit
  class ResponsesController < ApplicationController
    before_action :set_run
    before_action :set_response

    def show
      @sort = params[:sort]
      ordered_ids = ordered_response_ids
      current_index = ordered_ids.index(@response.id)
      @response_number = current_index + 1
      @reviews = @response.reviews.includes(:metric)
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
      if @run.judge_configured? && @sort == "score_asc"
        @run.responses
          .left_joins(:reviews)
          .group("completion_kit_responses.id")
          .order(Arel.sql("AVG(completion_kit_reviews.ai_score) ASC NULLS LAST"))
          .pluck(:id)
      elsif @run.judge_configured? && @sort != "none"
        @run.responses
          .left_joins(:reviews)
          .group("completion_kit_responses.id")
          .order(Arel.sql("AVG(completion_kit_reviews.ai_score) DESC NULLS LAST"))
          .pluck(:id)
      else
        @run.responses.order(:id).pluck(:id)
      end
    end
  end
end
