module CompletionKit
  module MetricAgreementExamples
    DEFAULT_JUDGE_EXAMPLE_LIMIT = 5

    module_function

    def for(metric, limit: 8)
      disagreements_for(metric, limit: limit)
    end

    def disagreements_for(metric, limit: 8)
      calibrations_for(metric, verdict: "disagree", limit: limit)
    end

    def borderlines_for(metric, limit: 6)
      calibrations_for(metric, verdict: "borderline", limit: limit)
    end

    def judge_examples_for(metric, exclude_response_id: nil, limit: DEFAULT_JUDGE_EXAMPLE_LIMIT)
      current_version = MetricVersion.current.find_by(metric_id: metric.id)
      return [] unless current_version

      relation = Calibration
                 .where(metric_id: metric.id, metric_version_id: current_version.id, excluded_from_examples: false)
                 .where.not(corrected_score: nil)
      relation = relation.where.not(response_id: exclude_response_id) if exclude_response_id
      map_examples(relation.includes(response: :reviews).order(created_at: :desc).limit(limit), metric)
        .reject { |example| example[:judge_score].nil? }
    end

    def calibrations_for(metric, verdict:, limit:)
      base = Calibration.where(metric_id: metric.id, verdict: verdict)
      current_version = MetricVersion.current.find_by(metric_id: metric.id)
      scoped = current_version ? base.where(metric_version_id: current_version.id) : base
      effective = scoped.exists? ? scoped : base
      map_examples(effective.includes(response: :reviews).order(created_at: :desc).limit(limit), metric)
    end

    def map_examples(relation, metric)
      relation.map do |cal|
        review = cal.response.reviews.find { |r| r.metric_id == metric.id }
        {
          id: cal.id,
          run_id: cal.run_id,
          response_id: cal.response_id,
          input: cal.response.input_data,
          output: cal.response.response_text,
          judge_score: review&.ai_score,
          judge_feedback: review&.ai_feedback,
          human_score: cal.corrected_score,
          human_note: cal.note
        }
      end
    end
  end
end
