module CompletionKit
  class JudgeVersion < ApplicationRecord
    STATES = %w[draft published].freeze

    belongs_to :metric
    has_many :calibrations, dependent: :destroy

    serialize :rubric_bands, coder: JSON

    validates :metric_id, presence: true
    validates :state, inclusion: { in: STATES }

    scope :current, -> { where(current: true) }
    scope :published, -> { where(state: "published") }
    scope :drafts, -> { where(state: "draft") }

    def self.ensure_current_for(metric)
      current.find_by(metric_id: metric.id) || create!(
        metric: metric,
        instruction: metric.instruction,
        rubric_bands: metric.rubric_bands,
        current: true,
        state: "published"
      )
    end

    def draft?
      state == "draft"
    end

    def published?
      state == "published"
    end

    def as_json(options = {})
      {
        id: id,
        metric_id: metric_id,
        instruction: instruction,
        rubric_bands: rubric_bands,
        current: current,
        state: state,
        source: source,
        created_at: created_at
      }
    end
  end
end
