module CompletionKit
  class MetricsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_metric, only: [:show, :edit, :update, :destroy, :add_few_shot, :remove_few_shot, :publish_draft, :suggest_variants, :dismiss_suggestion]

    def index
      @metrics = apply_tag_filter(Metric.includes(:metric_groups, :tags).order(:name))
      @available_starters = StarterMetrics.available
    end

    def starter_preview
      @starter = StarterMetrics.find(params[:key])
      return redirect_to(metrics_path, alert: "Unknown starter metric.") unless @starter
    end

    def adopt_starter
      starter = StarterMetrics.find(params[:key])
      return redirect_to(metrics_path, alert: "Unknown starter metric.") unless starter
      if Metric.exists?(name: starter.name)
        return redirect_to(metrics_path, alert: "A metric named \"#{starter.name}\" already exists.")
      end
      metric = Metric.create!(
        name: starter.name,
        instruction: starter.instruction,
        rubric_bands: starter.rubric_bands
      )
      redirect_to metric_path(metric), notice: "Added the \"#{starter.name}\" starter. Tweak any band before you run a judge against it."
    end

    def dismiss_starter
      starter = StarterMetrics.find(params[:key])
      return redirect_to(metrics_path, alert: "Unknown starter metric.") unless starter
      StarterMetricDismissal.find_or_create_by(starter_key: starter.key)
      redirect_to metrics_path, notice: "Dismissed \"#{starter.name}\". It won't appear here again."
    end

    def show
      @published_judge_version = JudgeVersion.published.where(metric_id: @metric.id, current: true).first
      disagreements_scope = Calibration.where(metric_id: @metric.id, verdict: "disagree")
      disagreements_scope = disagreements_scope.where(judge_version_id: @published_judge_version.id) if @published_judge_version
      @disagreements = disagreements_scope.includes(response: [:reviews, :run])
                                          .order(created_at: :desc)
                                          .limit(50)
      @edit_draft = JudgeVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @suggestion_draft = JudgeVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @improve_disagreement_count = @disagreements.size
    end

    def new
      @metric = Metric.new
    end

    def edit
      @suggestion_draft = JudgeVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @edit_draft = JudgeVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @published_judge_version = JudgeVersion.published.where(metric_id: @metric.id, current: true).first
    end

    def create
      @metric = Metric.new(metric_params)

      if @metric.save
        redirect_to metric_path(@metric), notice: "Metric was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @metric.update(metric_params)
        redirect_to metric_path(@metric), notice: "Metric was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @metric.destroy
      redirect_to metrics_path, notice: "Metric was successfully destroyed."
    end

    def suggest_variants
      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      disagreement_count = Calibration.where(metric_id: @metric.id, verdict: "disagree").count
      if disagreement_count.zero?
        redirect_to target, alert: "Mark at least one row as Disagree before asking the model to suggest a change."
        return
      end

      JudgeVersion.drafts.where(metric_id: @metric.id, source: "suggestion").destroy_all

      generator = JudgeVariantGenerator.new(@metric, count: 1)
      variants = generator.call
      if variants.empty?
        redirect_to target, alert: "The model returned no usable variants. Try again with a different model."
        return
      end
      generator.persist!(variants)
      redirect_to target, notice: "Drafted a new version. Review it below."
    end

    def dismiss_suggestion
      draft = JudgeVersion.drafts.where(metric_id: @metric.id).find_by(id: params[:draft_id])
      draft&.destroy
      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      redirect_to target, notice: "Dismissed."
    end

    def publish_draft
      scope = JudgeVersion.drafts.where(metric_id: @metric.id)
      draft = params[:draft_id].present? ? scope.find_by(id: params[:draft_id]) : scope.order(created_at: :desc).first

      if draft.nil?
        redirect_to metric_path(@metric), alert: "No draft to publish."
        return
      end

      JudgeVersion.transaction do
        JudgeVersion.where(metric_id: @metric.id, state: "published").update_all(current: false)
        draft.update!(state: "published", current: true)
        @metric.update_columns(
          instruction: draft.instruction,
          rubric_bands: Array(draft.rubric_bands).to_json
        )
      end

      redirect_to metric_path(@metric), notice: "This judge version is now live."
    end

    def add_few_shot
      calibration = Calibration.where(metric_id: @metric.id, verdict: "disagree").find(params[:calibration_id])
      review = calibration.response.reviews.find_by(metric_id: @metric.id)
      examples = Array(@metric.few_shot_examples)
      examples << {
        "input" => calibration.response.input_data.to_s.truncate(2000),
        "response" => calibration.response.response_text.to_s.truncate(2000),
        "judge_score" => review&.ai_score&.to_f,
        "judge_feedback" => review&.ai_feedback.to_s.truncate(1000),
        "human_score" => calibration.corrected_score&.to_f,
        "human_note" => calibration.note.to_s.truncate(1000),
        "calibration_id" => calibration.id,
        "added_at" => Time.current.utc.iso8601
      }
      @metric.update!(few_shot_examples: examples)
      redirect_to metric_path(@metric), notice: "Got it. The judge will remember this next time it grades."
    end

    def remove_few_shot
      cal_id = params[:calibration_id].to_i
      remaining = Array(@metric.few_shot_examples).reject { |fs| fs["calibration_id"].to_i == cal_id }
      @metric.update!(few_shot_examples: remaining)
      redirect_to metric_path(@metric), notice: "Forgotten. The judge won't see this case next time."
    end

    private

    def set_metric
      @metric = Metric.find(params[:id])
    end

    def metric_params
      params.require(:metric).permit(:name, :instruction,
        rubric_bands: [:stars, :description], tag_names: [])
    end
  end
end
