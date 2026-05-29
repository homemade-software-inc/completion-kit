module CompletionKit
  class Response < ApplicationRecord
    include HasJobStatus

    belongs_to :run
    has_many :reviews, dependent: :destroy
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    delegate :prompt, to: :run

    validates :response_text, presence: true, if: :succeeded?

    before_validation :set_default_status, on: :create

    after_save_commit :broadcast_row_update, unless: :destroyed?
    after_save_commit :broadcast_run_progress, if: :should_broadcast_progress?

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
      reviewed_metric_ids = reviews.where(status: HasJobStatus::TERMINAL_STATUSES).pluck(:metric_id).uniq
      (metric_ids - reviewed_metric_ids).empty?
    end

    private

    def broadcast_row_update
      run.broadcast_response_update(self)
    end

    def broadcast_run_progress
      run.broadcast_progress
    end

    def should_broadcast_progress?
      saved_change_to_status? && terminal?
    end
  end
end
