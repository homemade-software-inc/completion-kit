module CompletionKit
  class MetricVersion < ApplicationRecord
    STATES = %w[draft published].freeze

    belongs_to :metric
    has_many :calibrations, dependent: :destroy

    serialize :rubric_bands, coder: JSON

    before_validation :assign_version_number, on: :create

    validates :metric_id, presence: true
    validates :state, inclusion: { in: STATES }
    validates :version_number, presence: true, uniqueness: { scope: :metric_id }

    scope :current, -> { where(current: true) }
    scope :published, -> { where(state: "published") }
    scope :drafts, -> { where(state: "draft") }

    def self.ensure_current_for(metric)
      current.find_by(metric_id: metric.id) || create!(
        metric: metric,
        instruction: metric.instruction,
        rubric_bands: metric.rubric_bands,
        current: true,
        state: "published",
        published_at: Time.current
      )
    end

    def draft?
      state == "draft"
    end

    def published?
      state == "published"
    end

    def version_label
      "v#{version_number}"
    end

    def change_summary_against(previous)
      return nil if previous.nil?

      instruction_changed = previous.instruction.to_s.strip != instruction.to_s.strip
      rubric_changes = rubric_band_change_count(previous)
      return nil unless instruction_changed || rubric_changes.positive?

      dimensions = []
      dimensions << "instruction" if instruction_changed
      dimensions << "rubric" if rubric_changes.positive?

      words_changed = 0
      if instruction_changed
        old_words = previous.instruction.to_s.split
        new_words = instruction.to_s.split
        words_changed = (old_words - new_words).size + (new_words - old_words).size
      end

      magnitude = if rubric_changes >= 2 || (instruction_changed && rubric_changes >= 1) || words_changed >= 15
        :major
      elsif rubric_changes == 1 || words_changed >= 4
        :minor
      else
        :trivial
      end

      { magnitude: magnitude, label: "#{magnitude.to_s.capitalize} #{dimensions.to_sentence} changes" }
    end

    def publish!
      MetricVersion.transaction do
        self.class.where(metric_id: metric_id).where.not(id: id).update_all(current: false)
        reload
        update!(state: "published", current: true, published_at: published_at || Time.current)
        metric.update_columns(
          instruction: instruction,
          rubric_bands: Array(rubric_bands).to_json
        )
      end
      self
    end

    def revert!
      raise ArgumentError, "only a published version can be reverted to" unless published?
      audit = nil
      MetricVersion.transaction do
        audit = self.class.create!(
          metric: metric,
          instruction: instruction,
          rubric_bands: rubric_bands,
          state: "draft",
          source: "revert"
        )
        audit.publish!
      end
      audit
    end

    def as_json(options = {})
      {
        id: id,
        metric_id: metric_id,
        version_number: version_number,
        instruction: instruction,
        rubric_bands: rubric_bands,
        current: current,
        state: state,
        source: source,
        published_at: published_at,
        created_at: created_at
      }
    end

    private

    def rubric_band_change_count(previous)
      prev = Metric.normalize_rubric_bands(previous.rubric_bands)
      curr = Metric.normalize_rubric_bands(rubric_bands)
      prev.zip(curr).count { |p, c| p["description"].to_s.strip != c["description"].to_s.strip }
    end

    def assign_version_number
      return if version_number.present?
      max = self.class.where(metric_id: metric_id).maximum(:version_number).to_i
      self.version_number = max + 1
    end
  end

end
