module CompletionKit
  class RunsController < ApplicationController
    before_action :set_run, only: [:show, :edit, :update, :destroy, :generate, :judge]
    before_action :load_form_collections, only: [:new, :edit, :create, :update]

    def index
      @runs = Run.includes(:prompt, :dataset, responses: :reviews).order(created_at: :desc)
    end

    def show
      @responses = if @run.judge_configured? && params[:sort] == "score_asc"
                     @run.responses
                       .left_joins(:reviews)
                       .includes(:reviews)
                       .group("completion_kit_responses.id")
                       .order(Arel.sql("AVG(completion_kit_reviews.ai_score) ASC NULLS LAST"))
                   elsif @run.judge_configured?
                     @run.responses
                       .left_joins(:reviews)
                       .includes(:reviews)
                       .group("completion_kit_responses.id")
                       .order(Arel.sql("AVG(completion_kit_reviews.ai_score) DESC NULLS LAST"))
                   else
                     @run.responses.includes(:reviews).order(:id)
                   end
    end

    def new
      @run = Run.new(prompt_id: params[:prompt_id])
    end

    def edit
    end

    def create
      @run = Run.new(run_params)

      if @run.save
        redirect_to run_path(@run), notice: "Run created. Review the configuration below, then start when ready."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @run.update(run_params)
        redirect_to @run, notice: "Run was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @run.destroy
      redirect_to runs_path, notice: "Run was successfully destroyed."
    end

    def generate
      if @run.generate_responses!
        redirect_to @run, notice: "Responses generated successfully."
      else
        redirect_to @run, alert: @run.errors.full_messages.to_sentence.presence || "Failed to generate responses."
      end
    end

    def judge
      if params[:run].present?
        @run.update(params.require(:run).permit(:judge_model, :criteria_id))
      end

      if @run.judge_responses!
        redirect_to @run, notice: "Judging completed successfully."
      else
        redirect_to @run, alert: @run.errors.full_messages.to_sentence.presence || "Failed to judge responses."
      end
    end

    private

    def set_run
      @run = Run.find(params[:id])
    end

    def load_form_collections
      @prompts = Prompt.order(:name)
      @datasets = Dataset.order(:name)
      @criterias = Criteria.includes(:metrics).order(:name)
    end

    def run_params
      params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, :criteria_id)
    end
  end
end
