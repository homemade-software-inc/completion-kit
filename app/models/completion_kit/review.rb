module CompletionKit
  class Review < ApplicationRecord
    include HasJobStatus

    belongs_to :response
    belongs_to :metric, optional: true
    belongs_to :metric_version, optional: true
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    validates :metric_name, presence: true
    validates :metric_version, presence: true
    validates :ai_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    before_validation :set_default_status

    after_save_commit :broadcast_parent_row_update, unless: :destroyed?
    after_save_commit :broadcast_run_progress, if: :should_broadcast_progress?

    def check?
      effective_metric_type == "check"
    end

    def effective_metric_type
      metric_version&.metric_type || metric&.metric_type
    end

    def stale_against_current_judge?
      return false unless metric_id && metric_version
      current_number = MetricVersion.current.where(metric_id: metric_id).limit(1).pick(:version_number)
      return false if current_number.nil?
      metric_version.version_number != current_number
    end

    def as_json(options = {})
      {
        id: id, response_id: response_id, metric_id: metric_id,
        metric_version_id: metric_version_id,
        metric_name: metric_name, ai_score: ai_score, passed: passed,
        ai_feedback: ai_feedback, status: status, attempts: attempts,
        error: error_payload
      }
    end

    private

    def broadcast_parent_row_update
      safely_broadcast { response.run.broadcast_response_update(response) }
    end

    def broadcast_run_progress
      safely_broadcast { response.run.broadcast_progress }
    end

    def should_broadcast_progress?
      saved_change_to_status? && terminal?
    end

    def safely_broadcast
      yield
    rescue StandardError => e
      Rails.logger.error("[CompletionKit] review ##{id} broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
