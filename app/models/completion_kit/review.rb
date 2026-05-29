module CompletionKit
  class Review < ApplicationRecord
    include HasJobStatus

    belongs_to :response
    belongs_to :metric, optional: true
    belongs_to :metric_version, optional: true
    has_many :dashboard_dismissals, as: :dismissable, dependent: :destroy

    validates :metric_name, presence: true
    validates :ai_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    before_validation :set_default_status

    def stale_against_current_judge?
      return false unless metric_id && metric_version_id
      current_id = MetricVersion.current.where(metric_id: metric_id).limit(1).pick(:id)
      return false if current_id.nil?
      metric_version_id != current_id
    end

    def as_json(options = {})
      {
        id: id, response_id: response_id, metric_id: metric_id,
        metric_version_id: metric_version_id,
        metric_name: metric_name, ai_score: ai_score,
        ai_feedback: ai_feedback, status: status, attempts: attempts,
        error: error_payload
      }
    end
  end
end
