module CompletionKit
  class Response < ApplicationRecord
    include HasJobStatus

    belongs_to :run
    has_many :reviews, dependent: :destroy
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    delegate :prompt, to: :run

    validates :response_text, presence: true, if: :requires_response_text?

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
      reviews.any? { |r| r.ai_score.present? || !r.passed.nil? }
    end

    def checks_total
      reviews.count { |r| !r.passed.nil? }
    end

    def checks_passed
      reviews.count { |r| r.passed == true }
    end

    def checks_failed
      reviews.count { |r| r.passed == false }
    end

    def fully_reviewed?
      metric_ids = run.metric_ids
      return true if metric_ids.empty?
      reviewed_metric_ids = reviews.where(status: HasJobStatus::TERMINAL_STATUSES).pluck(:metric_id).uniq
      (metric_ids - reviewed_metric_ids).empty?
    end

    private

    def requires_response_text?
      succeeded? && !run&.judge_only?
    end

    def broadcast_row_update
      safely_broadcast { run.broadcast_response_update(self) }
    end

    def broadcast_run_progress
      safely_broadcast { run.broadcast_progress }
    end

    def should_broadcast_progress?
      saved_change_to_status? && terminal?
    end

    def safely_broadcast
      yield
    rescue StandardError => e
      Rails.logger.error("[CompletionKit] response ##{id} broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
