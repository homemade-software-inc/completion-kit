module CompletionKit
  class TestResultMetricAssessment < ApplicationRecord
    STATUSES = %w[pending evaluated reviewed failed].freeze

    belongs_to :test_result
    belongs_to :metric, optional: true

    validates :metric_name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :ai_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 5, allow_nil: true }
    validates :human_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5, allow_nil: true }

    before_validation :set_default_status

    def apply_human_review!(reviewer_name:, score:, feedback:)
      update!(
        human_reviewer_name: reviewer_name,
        human_score: score,
        human_feedback: feedback,
        human_reviewed_at: Time.current,
        status: ai_score.present? ? "reviewed" : "pending"
      )
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
