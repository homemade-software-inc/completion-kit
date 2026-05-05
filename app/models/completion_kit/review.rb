module CompletionKit
  class Review < ApplicationRecord
    STATUSES = %w[pending retrying succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    belongs_to :response
    belongs_to :metric, optional: true

    validates :metric_name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :ai_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    before_validation :set_default_status

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def succeeded?
      status == "succeeded"
    end

    def error_payload
      return nil if error_class.blank?
      { provider: error_provider, class: error_class, status: error_status, message: error_message }
    end

    def as_json(options = {})
      {
        id: id, response_id: response_id, metric_id: metric_id,
        metric_name: metric_name, ai_score: ai_score,
        ai_feedback: ai_feedback, status: status, attempts: attempts,
        error: error_payload
      }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
