module CompletionKit
  class Prompt < ApplicationRecord
    belongs_to :metric_group, class_name: "CompletionKit::MetricGroup", optional: true
    has_many :test_runs, dependent: :destroy
    has_many :test_results, through: :test_runs
    has_many :test_result_metric_assessments, through: :test_results, source: :metric_assessments

    serialize :rubric_bands, coder: JSON

    validates :name, presence: true
    validates :template, presence: true
    validates :llm_model, presence: true
    validates :assessment_model, presence: true
    validates :family_key, presence: true
    validates :version_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

    before_validation :assign_family_key, on: :create
    before_validation :assign_version_number, on: :create
    before_validation :set_defaults

    scope :current_versions, -> { where(current: true).order(created_at: :desc) }

    LegacyMetric = Struct.new(:id, :name, :criteria, :rubric_text, :rubric_bands, :evaluation_steps, keyword_init: true) do
      def persisted?
        false
      end

      def rubric_bands_for_form
        CompletionKit::Metric.normalize_rubric_bands(rubric_bands)
      end

      def display_rubric_text
        CompletionKit::Metric.rubric_text_for(rubric_bands_for_form)
      end
    end

    def self.available_models(provider: nil)
      ApiConfig.available_models(provider: provider)
    end

    def self.current_for(identifier)
      current_versions.find_by(family_key: identifier) || current_versions.find_by!(name: identifier)
    end

    def variables
      CsvProcessor.extract_variables(self)
    end

    def version_label
      "v#{version_number}"
    end

    def display_name
      "#{name} #{version_label}"
    end

    def family_versions
      self.class.where(family_key: family_key).order(version_number: :desc, created_at: :desc)
    end

    def assessment_metrics
      metrics = metric_group&.ordered_metrics.to_a || []
      return metrics if metrics.any?

      [legacy_metric]
    end

    def effective_review_guidance
      review_guidance.to_s
    end

    def effective_rubric_bands
      Metric.normalize_rubric_bands(rubric_bands.presence || Metric.default_rubric_bands)
    end

    def effective_rubric_text
      rubric_text.presence || Metric.rubric_text_for(effective_rubric_bands)
    end

    def clone_as_new_version(overrides = {})
      self.class.create!(
        {
          name: name,
          description: description,
          template: template,
          llm_model: llm_model,
          assessment_model: assessment_model,
          review_guidance: review_guidance,
          rubric_text: rubric_text,
          rubric_bands: rubric_bands,
          metric_group_id: metric_group_id,
          family_key: family_key,
          version_number: next_version_number,
          current: false,
          published_at: nil
        }.merge(overrides.compact)
      )
    end

    def publish!
      transaction do
        self.class.where(family_key: family_key).where.not(id: id).update_all(current: false)
        update!(current: true, published_at: Time.current)
      end
    end

    def human_review_examples(metric:, excluding_test_result_id: nil, limit: 5)
      return [] unless metric.respond_to?(:id) && metric.id.present?

      scope = test_result_metric_assessments.where(metric_id: metric.id).where.not(human_score: nil)
      scope = scope.where.not(test_result_id: excluding_test_result_id) if excluding_test_result_id.present?

      scope.includes(:test_result).order(human_reviewed_at: :desc, updated_at: :desc).limit(limit).map do |assessment|
        {
          input_data: assessment.test_result.input_data,
          output_text: assessment.test_result.output_text,
          human_score: assessment.human_score,
          human_feedback: assessment.human_feedback
        }
      end
    end

    private

    def assign_family_key
      self.family_key ||= SecureRandom.uuid
    end

    def assign_version_number
      self.version_number ||= next_version_number
    end

    def next_version_number
      self.class.where(family_key: family_key).maximum(:version_number).to_i + 1
    end

    def set_defaults
      self.current = true if current.nil?
      self.assessment_model ||= llm_model.presence || CompletionKit.config.judge_model
      self.review_guidance ||= ""
      self.rubric_bands = Metric.default_rubric_bands if rubric_bands.blank? && rubric_text.blank? && metric_group_id.blank?
      self.rubric_text = Metric.rubric_text_for(rubric_bands) if rubric_bands.present?
      self.published_at ||= Time.current if current?
    end

    def legacy_metric
      LegacyMetric.new(
        name: "Overall quality",
        criteria: effective_review_guidance,
        rubric_text: effective_rubric_text,
        rubric_bands: effective_rubric_bands,
        evaluation_steps: []
      )
    end
  end
end
