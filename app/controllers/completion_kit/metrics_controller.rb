module CompletionKit
  class MetricsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_metric, only: [:show, :edit, :update, :destroy, :add_few_shot, :publish_draft]

    def index
      @metrics = apply_tag_filter(Metric.includes(:metric_groups, :tags).order(:name))
    end

    def show
      @disagreements = Calibration.where(metric_id: @metric.id, verdict: "disagree")
                                  .includes(response: [:reviews, :run])
                                  .order(created_at: :desc)
                                  .limit(50)
      @latest_draft = JudgeVersion.drafts.where(metric_id: @metric.id).order(created_at: :desc).first
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

    def publish_draft
      draft = JudgeVersion.drafts.where(metric_id: @metric.id).order(created_at: :desc).first
      if draft.nil?
        redirect_to metric_path(@metric), alert: "No draft to publish."
        return
      end

      JudgeVersion.transaction do
        JudgeVersion.where(metric_id: @metric.id, state: "published").update_all(current: false)
        draft.update!(state: "published", current: true)
      end

      redirect_to metric_path(@metric), notice: "Draft published as the current judge version."
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
      redirect_to metric_path(@metric), notice: "Added as a judge few-shot."
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
