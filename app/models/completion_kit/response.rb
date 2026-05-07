module CompletionKit
  class Response < ApplicationRecord
    STATUSES = %w[pending retrying succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    belongs_to :run
    has_many :reviews, dependent: :destroy

    delegate :prompt, to: :run

    validates :response_text, presence: true, if: :succeeded?
    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def succeeded?
      status == "succeeded"
    end

    def as_json(options = {})
      {
        id: id, run_id: run_id, input_data: input_data,
        response_text: response_text, expected_output: expected_output,
        created_at: created_at, score: score, reviewed: reviewed?,
        reviews: reviews.map(&:as_json),
        status: status, attempts: attempts, row_index: row_index,
        error: error_payload
      }
    end

    def score
      scores = reviews.select { |r| r.ai_score.present? }.map { |r| r.ai_score.to_f }
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def reviewed?
      reviews.any? { |r| r.ai_score.present? }
    end

    def fully_reviewed?
      metric_ids = run.metric_ids
      return true if metric_ids.empty?
      reviewed_metric_ids = reviews.where(status: Review::TERMINAL_STATUSES).pluck(:metric_id).uniq
      (metric_ids - reviewed_metric_ids).empty?
    end

    def error_payload
      return nil if error_class.blank?
      { provider: error_provider, class: error_class, status: error_status, message: error_message }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
