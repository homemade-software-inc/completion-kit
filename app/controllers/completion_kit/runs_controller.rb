module CompletionKit
  class RunsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_run, only: [:show, :edit, :update, :destroy, :generate, :suggest, :retry_failures, :rerun, :refresh_status]
    before_action :load_form_collections, only: [:new, :edit, :create, :update]

    def index
      @runs = apply_tag_filter(Run.includes(:prompt, :dataset, :tags, responses: :reviews).order(created_at: :desc))
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
        @run.replace_metrics!(params[:run][:metric_ids])
        redirect_to run_path(@run), notice: "Run was successfully created."
      else
        load_form_collections
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @run.responses.any?
        attrs = run_params.except(:metric_ids).to_h
        attrs.delete("name") if attrs["name"].to_s == @run.name.to_s
        new_run = Run.create!(attrs.merge(status: "pending"))
        new_run.replace_metrics!(params[:run][:metric_ids]) if params[:run].key?(:metric_ids)
        redirect_to run_path(new_run), notice: "Saved as a new run. The previous run and its results are preserved."
      elsif @run.update(run_params.except(:metric_ids))
        @run.replace_metrics!(params[:run][:metric_ids]) if params[:run].key?(:metric_ids)
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
      if @run.start!
        redirect_to run_path(@run)
      else
        redirect_to run_path(@run), alert: @run.failure_summary || @run.errors.full_messages.to_sentence
      end
    end

    def rerun
      new_run = Run.create!(
        prompt_id: @run.prompt_id,
        dataset_id: @run.dataset_id,
        judge_model: @run.judge_model,
        temperature: @run.temperature,
        status: "pending"
      )
      new_run.replace_metrics!(@run.metric_ids)
      if new_run.start!
        redirect_to run_path(new_run), notice: "Re-running with the same configuration."
      else
        redirect_to run_path(new_run), alert: new_run.failure_summary || "Could not start the new run."
      end
    end

    def refresh_status
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "run_status_header",
            partial: "completion_kit/runs/status_header",
            locals: { run: @run }
          )
        end
      end
    end

    def suggest
      service = PromptImprovementService.new(@run)
      result = service.suggest
      suggestion = @run.suggestions.create!(
        prompt: @run.prompt,
        reasoning: result["reasoning"],
        suggested_template: result["suggested_template"],
        original_template: result["original_template"]
      )
      redirect_to suggestion_path(suggestion, from: "run")
    end

    def retry_failures
      scope = @run.responses.where(status: "failed")
      scope = scope.where(id: params[:only]) if params[:only].present?

      ActiveRecord::Base.transaction do
        failed_response_ids = scope.pluck(:id)
        Review.where(response_id: failed_response_ids, status: "failed").update_all(
          status: "pending",
          attempts: 0,
          error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
          ai_score: nil, ai_feedback: nil
        )
        scope.update_all(
          status: "pending",
          attempts: 0,
          error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
          response_text: nil
        )
        @run.update!(status: "running")
        failed_response_ids.each { |rid| GenerateRowJob.perform_later(@run.id, rid) }
      end

      @run.send(:broadcast_ui)
      redirect_to run_path(@run)
    end

    private

    def set_run
      @run = Run.find(params[:id])
    end

    def load_form_collections
      @prompts = Prompt.order(:name)
      @datasets = Dataset.order(:name)
      @metric_groups = MetricGroup.includes(:metrics).order(:name)
      @all_metrics = Metric.includes(:tags).order(:name)
    end

    def run_params
      params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, :temperature, metric_ids: [], tag_names: [])
    end

  end
end
