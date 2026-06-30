module CompletionKit
  class MetricsController < ApplicationController
    include CompletionKit::TagFiltering
    before_action :set_metric, only: [:show, :edit, :update, :destroy, :publish_draft, :suggest_variants, :dismiss_suggestion, :exclude_example]
    before_action :ensure_examples_from_reviews_enabled, only: [:exclude_example]

    def index
      @metrics = apply_tag_filter(Metric.includes(:metric_groups, :tags).order(:name))
      @available_starters = StarterMetrics.available
      @current_versions = MetricVersion.published.current.where(metric_id: @metrics.map(&:id)).index_by(&:metric_id)
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
        rubric_bands: starter.rubric_bands,
        metric_type: starter.metric_type || "llm_judge",
        check_config: starter.check_config
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
      @edit_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @suggestion_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @versions = MetricVersion.where(metric_id: @metric.id).order(version_number: :desc).to_a
      if @metric.check?
        @improve_disagreement_count = 0
        @guiding_examples = []
      else
        @improve_disagreement_count = Agreement.where(metric_id: @metric.id, verdict: "disagree").count
        @guiding_examples = CompletionKit.config.judge_examples_from_reviews ? MetricAgreementExamples.judge_examples_for(@metric) : []
      end
    end

    def new
      @metric = Metric.new
    end

    def edit
      @suggestion_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "suggestion").order(created_at: :desc).first
      @edit_draft = MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").order(created_at: :desc).first
      @published_metric_version = MetricVersion.published.where(metric_id: @metric.id, current: true).first
      @improve_disagreement_count = @metric.check? ? 0 : Agreement.where(metric_id: @metric.id, verdict: "disagree").count

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
      meta_attrs = metric_params.except(:instruction, :rubric_bands, :check_config)

      unless @metric.update(meta_attrs)
        return render(:edit, status: :unprocessable_entity)
      end

      if @metric.check?
        update_check_definition
      else
        update_judge_definition
      end
    end

    def destroy
      @metric.destroy
      redirect_to metrics_path, notice: "Metric was successfully destroyed."
    end

    def suggest_variants
      if @metric.check?
        redirect_to metric_path(@metric), alert: "Checks are exact, so there is nothing to suggest."
        return
      end

      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      counts = Agreement.where(metric_id: @metric.id, verdict: %w[agree disagree]).group(:verdict).count
      if counts["disagree"].to_i.zero?
        redirect_to target, alert: "Mark at least one case as Disagree before asking the model to suggest a change."
        return
      end

      MetricSuggestionJob.perform_later(@metric.id)

      if params[:back_to] == "edit"
        redirect_to metric_path(@metric), notice: "Drafting a change from your reviews. It will appear here once it's tested."
      else
        render turbo_stream: turbo_stream.replace(
          "ck-suggestion-status-#{@metric.id}",
          partial: "completion_kit/metrics/suggestion_pending",
          locals: { metric: @metric, count: counts.values.sum }
        )
      end
    end

    def dismiss_suggestion
      draft = MetricVersion.drafts.where(metric_id: @metric.id).find_by(id: params[:draft_id])
      label = draft&.version_label
      draft&.destroy
      target = params[:back_to] == "edit" ? edit_metric_path(@metric) : metric_path(@metric)
      redirect_to target, notice: label ? "Discarded draft #{label}." : "Draft already gone."
    end

    def exclude_example
      agreement = Agreement.where(metric_id: @metric.id).find(params[:agreement_id])
      agreement.update!(excluded_from_examples: true)
      render turbo_stream: turbo_stream.replace(
        "ck-guiding-#{@metric.id}",
        partial: "completion_kit/metrics/guiding_examples",
        locals: { metric: @metric, examples: MetricAgreementExamples.judge_examples_for(@metric) }
      )
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
        redirect_to metric_path(@metric),
                    notice: "#{@metric.name} is back on #{version.version_label}. Its reviews count again; the ones you gave on #{previously_current.version_label} stay with that version."
      else
        redirect_to metric_path(@metric),
                    notice: "#{@metric.name} #{version.version_label} is now the published version."
      end
    end

    private

    def ensure_examples_from_reviews_enabled
      head :not_found unless CompletionKit.config.judge_examples_from_reviews
    end

    def update_judge_definition
      proposed_instruction = metric_params[:instruction]
      proposed_rubric = metric_params[:rubric_bands]
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
                    notice: "Saved as draft #{draft.version_label}. Publish to make these changes the metric's live version."
      else
        @metric.update!(instruction: new_instruction, rubric_bands: new_rubric)
        current_pub = MetricVersion.published.where(metric_id: @metric.id, current: true).first
        current_pub&.update!(instruction: @metric.instruction, rubric_bands: @metric.rubric_bands)
        redirect_to metric_path(@metric), notice: "Metric was successfully updated."
      end
    end

    def update_check_definition
      raw = metric_params[:check_config]
      proposed = raw.nil? ? nil : normalize_check_config(raw)

      unless !proposed.nil? && proposed != @metric.check_config
        return redirect_to(metric_path(@metric), notice: "Metric was successfully updated.")
      end

      if @metric.reviews.exists?
        MetricVersion.drafts.where(metric_id: @metric.id, source: "edit").destroy_all
        draft = MetricVersion.create!(
          metric: @metric, metric_type: "check", check_config: proposed,
          state: "draft", source: "edit", current: false
        )
        redirect_to edit_metric_path(@metric),
                    notice: "Saved as draft #{draft.version_label}. Publish to make these changes the metric's live version."
      else
        @metric.update!(check_config: proposed)
        current_pub = MetricVersion.published.where(metric_id: @metric.id, current: true).first
        current_pub&.update!(metric_type: "check", check_config: proposed)
        redirect_to metric_path(@metric), notice: "Metric was successfully updated."
      end
    end

    def set_metric
      @metric = Metric.find(params[:id])
    end

    def metric_params
      permitted = params.require(:metric).permit(:name, :instruction, :metric_type,
        rubric_bands: [:stars, :description],
        check_config: %i[check_kind target target_path value pattern json_path expected min max case_sensitive multiline trim],
        tag_names: [])
      permitted[:check_config] = normalize_check_config(permitted[:check_config]) if permitted.key?(:check_config)
      permitted
    end

    def normalize_check_config(config)
      hash = config.to_unsafe_h.stringify_keys
      %w[min max].each { |key| hash[key] = hash[key].to_i if hash[key].present? }
      %w[case_sensitive multiline trim].each { |key| hash[key] = ActiveModel::Type::Boolean.new.cast(hash[key]) if hash.key?(key) }
      hash.reject { |_, value| value.nil? || value == "" }
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
