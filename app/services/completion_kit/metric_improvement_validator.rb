module CompletionKit
  class MetricImprovementValidator
    ANSWER_KEY_LIMIT = 30

    def initialize(metric, candidate, scorer: nil)
      @metric = metric
      @candidate = candidate
      @scorer = scorer || method(:rescore)
    end

    def call
      key = answer_key
      rows = []
      key.each do |entry|
        begin
          score = @scorer.call(entry[:response], @candidate)
        rescue StandardError
          next
        end
        rows << classify(entry, score.to_i)
      end
      summarize(rows, key.size, key_capped?)
    end

    private

    def answer_key
      current = MetricVersion.current.find_by(metric_id: @metric.id)
      return [] unless current

      base = Calibration.where(metric_id: @metric.id, metric_version_id: current.id, verdict: %w[agree disagree])
      @key_size_before_cap = base.count
      base.includes(response: :reviews)
          .order(created_at: :desc)
          .limit(ANSWER_KEY_LIMIT)
          .filter_map do |cal|
        response = cal.response
        next unless response.response_text.present?
        review = response.reviews.find { |r| r.metric_id == @metric.id }
        position = cal.verdict == "disagree" ? cal.corrected_score : review&.ai_score
        next if position.nil?
        { response: response, verdict: cal.verdict, position: position }
      end
    end

    def key_capped?
      @key_size_before_cap.to_i > ANSWER_KEY_LIMIT
    end

    def classify(entry, candidate_score)
      matched = candidate_score == entry[:position].to_i
      outcome = if entry[:verdict] == "disagree"
        matched ? "fix" : "still_off"
      else
        matched ? "keep" : "break"
      end
      {
        "response_id" => entry[:response].id,
        "verdict" => entry[:verdict],
        "position" => entry[:position].to_i,
        "candidate_score" => candidate_score,
        "outcome" => outcome
      }
    end

    def summarize(rows, total, capped)
      fixes = rows.count { |r| r["outcome"] == "fix" }
      keeps = rows.count { |r| r["outcome"] == "keep" }
      breaks = rows.count { |r| r["outcome"] == "break" }
      still_off = rows.count { |r| r["outcome"] == "still_off" }
      agreements = rows.count { |r| r["verdict"] == "agree" }
      {
        "total" => total,
        "tested" => rows.size,
        "capped" => capped,
        "fixes" => fixes,
        "keeps" => keeps,
        "breaks" => breaks,
        "still_off" => still_off,
        "before" => agreements,
        "after" => fixes + keeps,
        "rows" => rows
      }
    end

    def rescore(response, candidate)
      run = response.run
      config = ApiConfig.for_model(run.judge_model).merge(judge_model: run.judge_model)
      rubric_text = Metric.rubric_text_for(Metric.normalize_rubric_bands(candidate.rubric_bands))
      result = JudgeService.new(config).evaluate(
        response.response_text,
        response.expected_output,
        run.prompt&.template,
        criteria: candidate.instruction.to_s,
        rubric_text: rubric_text,
        input_data: response.input_data
      )
      result[:score]
    end
  end
end
