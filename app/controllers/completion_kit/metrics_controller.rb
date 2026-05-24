module CompletionKit
  class MetricsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_metric, only: [:show, :edit, :update, :destroy, :add_few_shot, :publish_draft, :suggest_variants]

    def index
      @metrics = apply_tag_filter(Metric.includes(:metric_groups, :tags).order(:name))
    end

    def show
      @disagreements = Calibration.where(metric_id: @metric.id, verdict: "disagree")
                                  .includes(response: [:reviews, :run])
                                  .order(created_at: :desc)
                                  .limit(50)
      @latest_draft = JudgeVersion.drafts.where(metric_id: @metric.id).order(created_at: :desc).first
      @published_judge_version = JudgeVersion.published.where(metric_id: @metric.id, current: true).first
      @suggestion_drafts = JudgeVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc)
    end

    def new
      @metric = Metric.new
    end

    def edit
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
      generator = JudgeVariantGenerator.new(@metric)
      variants = generator.call
      if variants.empty?
        redirect_to metric_path(@metric), alert: "The model returned no usable variants. Try again with a different model."
        return
      end
      generator.persist!(variants)
      label = variants.length == 1 ? "alternative" : "alternatives"
      redirect_to metric_path(@metric), notice: "Wrote #{variants.length} #{label} for this metric. Pick one to make it live."
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
      redirect_to metric_path(@metric), notice: "Saved as a teaching example. The judge will see it next time it grades."
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
