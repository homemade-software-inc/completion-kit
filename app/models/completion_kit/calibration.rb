module CompletionKit
  class Calibration < ApplicationRecord
    VERDICTS = %w[agree disagree borderline].freeze

    belongs_to :run
    belongs_to :response
    belongs_to :metric, optional: true

    validates :verdict, presence: true, inclusion: { in: VERDICTS }
    validates :corrected_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    scope :for_response, ->(response) { where(response_id: response.id) }
    scope :for_metric, ->(metric) { where(metric_id: metric.id) }
    scope :by_anonymous_id, ->(anonymous_id) { where(anonymous_id: anonymous_id) }

    def self.upsert!(run_id:, response_id:, metric_id:, anonymous_id:, verdict:, corrected_score: nil, note: nil, judge_version_id: nil)
      attrs = {
        run_id: run_id,
        response_id: response_id,
        metric_id: metric_id,
        anonymous_id: anonymous_id,
        verdict: verdict,
        corrected_score: corrected_score,
        note: note,
        judge_version_id: judge_version_id
      }
      existing = find_by(run_id: run_id, response_id: response_id, metric_id: metric_id, anonymous_id: anonymous_id)
      if existing
        existing.update!(attrs)
        existing
      else
        create!(attrs)
      end
    end

    def as_json(options = {})
      {
        id: id,
        run_id: run_id,
        response_id: response_id,
        metric_id: metric_id,
        anonymous_id: anonymous_id,
        verdict: verdict,
        corrected_score: corrected_score,
        note: note,
        judge_version_id: judge_version_id,
        created_at: created_at,
        updated_at: updated_at
      }
    end
  end
end
