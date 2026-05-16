module CompletionKit
  # Read-only aggregate queries powering the standalone dashboard cards.
  # Each method is a small, scoped query — nothing here writes or caches.
  class DashboardStats
    # Runs per calendar day for the trailing `days` window, oldest first.
    # Always returns one entry per day (count 0 for quiet days) so callers
    # can render a fixed-width sparkline.
    def self.activity(days: 14)
      since = (days - 1).days.ago.to_date
      counts = Run.where("created_at >= ?", since.beginning_of_day)
                  .group("DATE(created_at)")
                  .count
      (0...days).map do |offset|
        date = since + offset
        { date: date, count: counts[date] || counts[date.to_s] || 0 }
      end
    end

    # The metric with the lowest average judge score across succeeded reviews
    # in the window — the prompt-engineering target. Returns nil when there
    # are no scored reviews. `response` is the single worst-scoring response
    # for that metric, for a deep link.
    def self.worst_metric(since:)
      averages = scored_reviews_since(since).group(:metric_name).average(:ai_score)
      return nil if averages.empty?

      name, avg = averages.min_by { |_, value| value }
      # averages is non-empty, so at least one review carries this
      # metric_name — worst is always present here.
      worst = scored_reviews_since(since)
              .where(metric_name: name)
              .order(:ai_score)
              .first
      {
        name: name,
        avg: avg.to_f.round(2),
        response: worst.response,
        score: worst.ai_score.to_f
      }
    end

    # Reviews that terminally failed in the window — parse failures, judge
    # truncations, provider errors. Invisible on the dashboard otherwise.
    def self.failed_review_count(since:)
      Review.where(status: "failed").where("created_at >= ?", since).count
    end

    # The most recent measurable change per prompt family — gains and
    # regressions both. For each family the comparison is:
    #   * latest scored version vs the published version, when a draft sits
    #     ahead of what's live ("is my work-in-progress better?")
    #   * published vs the previous scored version, when the latest version
    #     IS the published one ("did my last publish help?")
    # Biggest movement first. Empty until something has been iterated and
    # re-judged on both sides of the comparison.
    def self.prompt_changes(limit: 5)
      scores = Review.joins(response: :run)
                     .where(status: "succeeded")
                     .where.not(ai_score: nil)
                     .group("completion_kit_runs.prompt_id")
                     .average(:ai_score)
      return [] if scores.empty?

      Prompt.where(id: scores.keys).group_by(&:family_key).filter_map do |_key, versions|
        scored = versions.select { |v| scores[v.id] }.sort_by(&:version_number)
        next if scored.size < 2

        candidate = scored.last
        published = versions.find(&:current?)
        baseline =
          if published && published != candidate && scores[published.id]
            published
          else
            scored[-2]
          end

        delta = (scores[candidate.id] - scores[baseline.id]).to_f.round(2)
        next if delta.zero?

        {
          prompt: candidate,
          from_version: baseline.version_number,
          to_version: candidate.version_number,
          from_score: scores[baseline.id].to_f.round(2),
          to_score: scores[candidate.id].to_f.round(2),
          delta: delta
        }
      end.sort_by { |row| -row[:delta].abs }.first(limit)
    end

    def self.scored_reviews_since(since)
      Review.joins(:response)
            .where(status: "succeeded")
            .where("completion_kit_reviews.created_at >= ?", since)
            .where.not(ai_score: nil)
    end
    private_class_method :scored_reviews_since
  end
end
