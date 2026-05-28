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
      @published_metric_version = MetricVersion.ensure_current_for(@metric)
      @disagreements = Calibration.where(metric_id: @metric.id, verdict: "disagree")
                                  .includes(:metric_version, response: [:reviews, :run])
                                  .order(created_at: :desc)
                                  .limit(50)
      @edit_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @suggestion_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @improve_disagreement_count = Calibration.where(metric_id: @metric.id, verdict: "disagree").count
      @versions = MetricVersion.where(metric_id: @metric.id).order(version_number: :desc).to_a
    end

    def new
      @metric = Metric.new
    end

    def edit
      @suggestion_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @edit_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @published_metric_version = MetricVersion.published.where(metric_id: @metric.id, current: true).first

      if @edit_draft
        @metric.instruction = @edit_draft.instruction
        @metric.rubric_bands = @edit_draft.rubric_bands
      end
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
      judge_keys = %i[instruction rubric_bands]
      meta_attrs = metric_params.except(*judge_keys)
      proposed_instruction = metric_params[:instruction]
      proposed_rubric = metric_params[:rubric_bands]

      unless @metric.update(meta_attrs)
        return render(:edit, status: :unprocessable_entity)
      end

      current_instruction = @metric.instruction.to_s
      current_rubric = @metric.rubric_bands || []
      normalized_proposed_rubric = normalize_rubric_bands_for_update(proposed_rubric)

      instruction_changed = !proposed_instruction.nil? && proposed_instruction.to_s != current_instruction
      rubric_changed = !normalized_proposed_rubric.nil? && normalized_proposed_rubric != current_rubric

      unless instruction_changed || rubric_changed
        return redirect_to(metric_path(@metric), notice: "Metric was successfully updated.")
      end

      new_instruction = instruction_changed ? proposed_instruction.to_s : current_instruction
      new_rubric = rubric_changed ? normalized_proposed_rubric : current_rubric

      if @metric.reviews.exists?
        MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").destroy_all
        draft = MetricVersion.create!(
          metric: @metric, instruction: new_instruction, rubric_bands: new_rubric,
          state: "draft", source: "edit", current: false
        )
        redirect_to edit_metric_path(@metric),
                    notice: "Saved as draft #{draft.version_label}. Publish to push these changes to the live judge."
      else
        @metric.update!(instruction: new_instruction, rubric_bands: new_rubric)
        current_pub = MetricVersion.published.where(metric_id: @metric.id, current: true).first
        current_pub&.update!(instruction: @metric.instruction, rubric_bands: @metric.rubric_bands)
        redirect_to metric_path(@metric), notice: "Metric was successfully updated."
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

      MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").destroy_all

      generator = MetricVariantGenerator.new(@metric, count: 1)
      variants = generator.call
      if variants.empty?
        redirect_to target, alert: "The model returned no usable variants. Try again with a different model."
        return
      end
      generator.persist!(variants)
      redirect_to target, notice: "Drafted a new version. Review it below."
    end

    def dismiss_suggestion
      draft = MetricVersion.drafts.where(metric_id: @metric.id).find_by(id: params[:draft_id])
      draft&.destroy
      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      redirect_to target, notice: "Dismissed."
    end

    def publish_draft
      scope = MetricVersion.where(metric_id: @metric.id)
      version = if params[:draft_id].present?
                  scope.find_by(id: params[:draft_id])
                else
                  MetricVersion.drafts.where(metric_id: @metric.id).order(created_at: :desc).first
                end

      if version.nil?
        redirect_to metric_path(@metric), alert: "No version to publish."
        return
      end

      was_published_already = version.published?
      reverting = was_published_already && !version.current?
      previously_current = MetricVersion.current.find_by(metric_id: @metric.id)

      version.publish!

      if reverting
        prior_label = previously_current.version_label
        redirect_to metric_path(@metric),
                    notice: "Reverted to #{@metric.name} #{version.version_label}. Pinned cases still flow to the judge, and calibration verdicts collected against #{prior_label} stay tied to it."
      else
        redirect_to metric_path(@metric),
                    notice: "#{@metric.name} #{version.version_label} is now the published version."
      end
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

    def normalize_rubric_bands_for_update(bands)
      return nil if bands.nil?
      array = bands.is_a?(ActionController::Parameters) ? bands.to_unsafe_h.values : bands
      Array(array).map do |b|
        h = b.respond_to?(:to_unsafe_h) ? b.to_unsafe_h : b
        { "stars" => h["stars"].to_i, "description" => h["description"].to_s }
      end.sort_by { |b| -b["stars"] }
    end
  end
end
