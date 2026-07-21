module CompletionKit
  class RunsController < ApplicationController
    include CompletionKit::TagFiltering
    include CompletionKit::ResponseOrdering
    before_action :set_run, only: [:show, :edit, :update, :destroy, :generate, :suggest, :retry_failures, :rerun, :regrade, :refresh_status, :compare]
    before_action :load_form_collections, only: [:new, :edit, :create, :update]

    def index
      scope = Run.includes(:prompt, :dataset, :tags, responses: :reviews).order(created_at: :desc).display_scoped
      @runs = apply_tag_filter(scope)
    end

    RESPONSES_PER_PAGE = 100
    RESPONSE_PREVIEW_CHARS = 700

    def show
      @responses_total = @run.responses.count
      @responses_per_page = RESPONSES_PER_PAGE
      @responses_total_pages = [(@responses_total.to_f / RESPONSES_PER_PAGE).ceil, 1].max
      @responses_page = params[:page].to_s.to_i.clamp(1, @responses_total_pages)
      @responses_offset = (@responses_page - 1) * RESPONSES_PER_PAGE
      @responses = ordered_responses_relation(@run, params[:sort])
                     .with_body_preview(RESPONSE_PREVIEW_CHARS)
                     .includes(:reviews)
                     .limit(RESPONSES_PER_PAGE)
                     .offset(@responses_offset)
    end

    def new
      @run = Run.new(prompt_id: params[:prompt_id])
      prompt = Prompt.find_by(id: @run.prompt_id)
      if prompt
        last_run = Run.where(prompt_id: prompt.family_versions.ids).display_scoped.order(created_at: :desc).first
        @run.tag_names = last_run.tag_names if last_run
      end
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
      if @run.responses.any? && run_generation_changed?
        attrs = run_params.except(:metric_ids).to_h
        attrs.delete("name") if attrs["name"].to_s == @run.name.to_s
        new_run = Run.new(attrs.merge(status: "pending"))
        if new_run.save
          new_run.replace_metrics!(params[:run][:metric_ids]) if params[:run].key?(:metric_ids)
          redirect_to run_path(new_run), notice: "Saved as a new run. The previous run and its results are preserved."
        else
          @run.assign_attributes(run_params.except(:metric_ids))
          new_run.errors.each { |error| @run.errors.add(error.attribute, error.message) }
          load_form_collections
          render :edit, status: :unprocessable_entity
        end
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

    def compare
      other_id = params[:with]
      if other_id.blank?
        @other_runs = Run.where(dataset_id: @run.dataset_id, prompt_id: @run.prompt_id)
                          .where.not(id: @run.id)
                          .display_scoped
                          .order(created_at: :desc)
                          .limit(50)
        return render(:compare_picker)
      end

      @other_run = Run.find(other_id)
      @comparison = build_run_comparison(@run, @other_run)
      render(:compare)
    end

    def regrade
      if @run.regrade!
        redirect_to run_path(@run), notice: "Re-grading existing responses against the current metrics."
      else
        redirect_to run_path(@run), alert: "Nothing to re-grade. The run has no succeeded responses or no metrics attached."
      end
    end

    def rerun
      new_run = Run.create!(
        prompt_id: @run.prompt_id,
        dataset_id: @run.dataset_id,
        judge_model: @run.judge_model,
        temperature: @run.temperature,
        output_column: @run.output_column,
        expected_column: @run.expected_column,
        tag_names: @run.tag_names,
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
      if @run.prompt.nil?
        redirect_to run_path(@run), alert: "A run that only scores existing outputs has no prompt to improve."
        return
      end

      suggestion = @run.suggestions.create!(
        prompt: @run.prompt,
        original_template: @run.prompt.template,
        status: "pending"
      )
      PromptSuggestionJob.perform_later(suggestion.id)
      redirect_to suggestion_path(suggestion, from: "run")
    end

    def retry_failures
      if @run.stale_review_summary.any?
        redirect_to run_path(@run),
                    alert: "A metric has a newer version than the one this run was scored against. Retrying failed cases would mix scores from two versions in the same run. Use 'Re-run from scratch' to refresh everything against the current metrics."
        return
      end

      scope = @run.responses.where(status: "failed")
      scope = scope.where(id: params[:only]) if params[:only].present?

      ActiveRecord::Base.transaction do
        failed_response_ids = scope.pluck(:id)
        Review.where(response_id: failed_response_ids, status: "failed").update_all(
          status: "pending",
          attempts: 0,
          error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
          ai_score: nil, passed: nil, ai_feedback: nil
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

      @run.broadcast_ui
      redirect_to run_path(@run)
    end

    private

    def set_run
      @run = Run.find(params[:id])
    end

    def build_run_comparison(left, right)
      left_responses = left.responses.includes(:reviews).order(:row_index, :id)
      right_responses = right.responses.includes(:reviews).order(:row_index, :id)
      right_by_input = right_responses.each_with_object({}) { |r, h| h[r.input_data.to_s] ||= r }

      all_reviews = left_responses.flat_map(&:reviews) + right_responses.flat_map(&:reviews)
      metric_ids = all_reviews.map(&:metric_id).compact.uniq
      metric_versions = MetricVersion.where(id: all_reviews.map(&:metric_version_id).compact.uniq).index_by(&:id)

      rows = left_responses.map do |lr|
        rr = right_by_input[lr.input_data.to_s]
        {
          left_response: lr,
          right_response: rr,
          per_metric: metric_ids.map do |mid|
            l_review = lr.reviews.find { |r| r.metric_id == mid }
            r_review = rr && rr.reviews.find { |r| r.metric_id == mid }
            next nil if l_review.nil? && r_review.nil?
            anchor = l_review || r_review
            {
              metric_id: mid,
              metric_name: anchor.metric_name,
              kind: anchor.check? ? "check" : "llm_judge",
              left_score: l_review ? l_review.ai_score : nil,
              right_score: r_review ? r_review.ai_score : nil,
              left_passed: l_review&.passed,
              right_passed: r_review&.passed,
              left_version_label: version_label_for(l_review, metric_versions),
              right_version_label: version_label_for(r_review, metric_versions),
              delta: (l_review&.ai_score && r_review&.ai_score) ? (r_review.ai_score.to_f - l_review.ai_score.to_f).round(2) : nil,
              result_change: RunComparison.result_change(l_review&.passed, r_review&.passed)
            }
          end.compact
        }
      end
      { rows: rows, metric_ids: metric_ids }
    end

    def version_label_for(review, metric_versions)
      return nil if review.nil? || review.metric_version_id.nil?
      metric_versions[review.metric_version_id]&.version_label
    end

    def load_form_collections
      @prompts = Prompt.order(:name)
      @datasets = Dataset.order(:name)
      @metric_groups = MetricGroup.includes(:metrics).order(:name)
      @all_metrics = Metric.includes(:tags).order(:name)
    end

    def run_params
      params.require(:run).permit(:name, :prompt_id, :dataset_id, :judge_model, :temperature, :output_column, :expected_column, metric_ids: [], tag_names: [])
    end

    # Editing a run that already has results forks a new run — but only when a
    # field that affects generation or judging changed. Renaming or retagging is
    # pure metadata and updates the run in place.
    GENERATION_RUN_FIELDS = %i[prompt_id dataset_id judge_model temperature output_column expected_column].freeze

    def run_generation_changed?
      GENERATION_RUN_FIELDS.each do |field|
        next unless run_params.key?(field)
        return true if normalize_run_field(field, run_params[field]) != normalize_run_field(field, @run.public_send(field))
      end
      return false unless params[:run].key?(:metric_ids)
      Array(params[:run][:metric_ids]).map(&:to_i).reject(&:zero?).sort != @run.metric_ids.sort
    end

    def normalize_run_field(field, value)
      s = value.to_s.strip
      return nil if s.empty?
      case field
      when :temperature then s.to_f
      when :prompt_id, :dataset_id then s.to_i
      else s
      end
    end

  end
end
