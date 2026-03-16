module CompletionKit
  class Review < ApplicationRecord
    STATUSES = %w[pending evaluated failed].freeze

    belongs_to :response
    belongs_to :metric, optional: true

    validates :metric_name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :ai_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    before_validation :set_default_status

    def as_json(options = {})
      {
        id: id, response_id: response_id, metric_id: metric_id,
        metric_name: metric_name, ai_score: ai_score,
        ai_feedback: ai_feedback, status: status
      }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
