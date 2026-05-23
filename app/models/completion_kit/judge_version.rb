module CompletionKit
  class JudgeVersion < ApplicationRecord
    belongs_to :metric
    has_many :calibrations, dependent: :destroy

    serialize :rubric_bands, coder: JSON

    validates :metric_id, presence: true

    scope :current, -> { where(current: true) }

    def self.ensure_current_for(metric)
      current.find_by(metric_id: metric.id) || create!(
        metric: metric,
        instruction: metric.instruction,
        rubric_bands: metric.rubric_bands,
        current: true
      )
    end

    def as_json(options = {})
      {
        id: id,
        metric_id: metric_id,
        instruction: instruction,
        rubric_bands: rubric_bands,
        current: current,
        created_at: created_at
      }
    end
  end
end
