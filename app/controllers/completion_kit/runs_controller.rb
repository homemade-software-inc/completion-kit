module CompletionKit
  class RunsController < ApplicationController
    before_action :set_run, only: [:show, :edit, :update, :destroy, :generate, :judge, :suggest, :suggestion]
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
      @run = Run.new(run_params.except(:metric_ids))
      if @run.save
        replace_run_metrics(@run, params[:run][:metric_ids])
        redirect_to run_path(@run), notice: "Run was successfully created."
      else
        load_form_collections
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @run.responses.any?
        new_run = Run.create!(run_params.except(:metric_ids).to_h.merge(status: "pending"))
        replace_run_metrics(new_run, params[:run][:metric_ids]) if params[:run].key?(:metric_ids)
        redirect_to run_path(new_run), notice: "Saved as a new run. The previous run and its results are preserved."
      elsif @run.update(run_params.except(:metric_ids))
        replace_run_metrics(@run, params[:run][:metric_ids]) if params[:run].key?(:metric_ids)
        redirect_to run_path(@run), notice: "Run saved."
      else
        load_form_collections
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @run.destroy
      redirect_to runs_path, notice: "Run was successfully destroyed."
    end

    def generate
      @run.update!(status: "generating", progress_current: 0, progress_total: 0, error_message: nil)
      GenerateJob.perform_later(@run.id)
      redirect_to run_path(@run)
    end

    def judge
      if params[:run]
        @run.update(judge_model: params[:run][:judge_model])
      end
      JudgeJob.perform_later(@run.id)
      redirect_to run_path(@run)
    end

    def suggest
      service = PromptImprovementService.new(@run)
      result = service.suggest
      session["suggestion_#{@run.id}"] = result
      redirect_to suggestion_run_path(@run)
    end

    def suggestion
      @suggestion = session["suggestion_#{@run.id}"]
      redirect_to run_path(@run), alert: "No suggestion available. Generate one first." unless @suggestion
    end

    private

    def set_run
      @run = Run.find(params[:id])
    end

    def load_form_collections
      @prompts = Prompt.order(:name)
      @datasets = Dataset.order(:name)
      @criterias = Criteria.includes(:metrics).order(:name)
      @all_metrics = Metric.order(:name)
    end

    def run_params
      params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, metric_ids: [])
    end

    def replace_run_metrics(run, metric_ids)
      return unless metric_ids
      run.run_metrics.delete_all
      Array(metric_ids).reject(&:blank?).each_with_index do |metric_id, index|
        run.run_metrics.create!(metric_id: metric_id, position: index + 1)
      end
    end
  end
end
