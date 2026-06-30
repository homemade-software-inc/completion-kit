module CompletionKit
  module ResponseOrdering
    extend ActiveSupport::Concern

    private

    FAILED_CHECKS_SQL = "SUM(CASE WHEN completion_kit_reviews.passed IS FALSE THEN 1 ELSE 0 END)".freeze
    RUBRIC_AVG_SQL = "AVG(completion_kit_reviews.ai_score)".freeze

    def ordered_responses_relation(run, sort)
      return run.responses.order(:id) unless run.gradable?

      composite = if sort == "score_asc"
                    "#{FAILED_CHECKS_SQL} DESC, #{RUBRIC_AVG_SQL} ASC NULLS LAST"
                  else
                    "#{FAILED_CHECKS_SQL} ASC, #{RUBRIC_AVG_SQL} DESC NULLS LAST"
                  end

      run.responses
         .left_joins(:reviews)
         .group("completion_kit_responses.id")
         .order(Arel.sql("#{composite}, completion_kit_responses.id ASC"))
    end
  end
end
