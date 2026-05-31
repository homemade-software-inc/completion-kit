module CompletionKit
  class Agreement < ApplicationRecord
    VERDICTS = %w[agree disagree borderline].freeze

    belongs_to :run
    belongs_to :response
    belongs_to :metric
    belongs_to :metric_version

    validates :verdict, presence: true, inclusion: { in: VERDICTS }
    validates :response_id,
              uniqueness: { scope: [:metric_id, :created_by] }
    validate :corrected_score_required_when_disagreeing
    validate :corrected_score_within_rubric

    scope :for_run, ->(run_id) { where(run_id: run_id) }
    scope :for_metric, ->(metric_id) { where(metric_id: metric_id) }

    def as_json(options = {})
      {
        id: id,
        run_id: run_id,
        response_id: response_id,
        metric_id: metric_id,
        metric_version_id: metric_version_id,
        verdict: verdict,
        corrected_score: corrected_score,
        note: note,
        created_by: created_by,
        created_at: created_at
      }
    end

    private

    def corrected_score_required_when_disagreeing
      return unless verdict == "disagree"
      errors.add(:corrected_score, "must be set when disagreeing with the judge") if corrected_score.blank?
    end

    def corrected_score_within_rubric
      return if corrected_score.blank?
      score = corrected_score.to_f
      errors.add(:corrected_score, "must be between 1 and 5") unless score >= 1 && score <= 5
    end
  end
end
