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
    # in the window — the prompt-engineering target. Dismissed metrics are
    # skipped while their average holds at or above the score snapshotted when
    # they were dismissed; a metric that regresses below that baseline
    # resurfaces and its stale dismissal is cleared. Returns nil when nothing
    # qualifies. `response` is the single worst-scoring response, for a deep
    # link.
    def self.worst_metric(since:)
      averages = scored_reviews_since(since)
                 .joins(:metric)
                 .group("completion_kit_metrics.id")
                 .average(:ai_score)
      return nil if averages.empty?

      dismissals = metric_dismissals
      metrics = Metric.where(id: averages.keys).index_by(&:id)

      averages.sort_by { |_id, avg| avg }.each do |metric_id, avg|
        rounded = avg.to_f.round(2)
        dismissal = dismissals[metric_id]
        next if dismissal && rounded >= dismissal.baseline_score.to_f

        dismissal&.destroy
        worst = scored_reviews_since(since).where(metric_id: metric_id).order(:ai_score).first
        metric = metrics[metric_id]
        return {
          metric: metric,
          name: metric.name,
          avg: rounded,
          response: worst.response,
          score: worst.ai_score.to_f
        }
      end
      nil
    end

    # The rounded average judge score for one metric across the window, or nil
    # when it has no scored reviews. Used to snapshot a dismissal's baseline.
    def self.metric_average(metric_id, since:)
      scored_reviews_since(since).where(metric_id: metric_id).average(:ai_score)&.to_f&.round(2)
    end

    # Everything that terminally failed in the window across all three
    # surfaces — failed runs, failed generations, failed judge reviews —
    # excluding any the user has dismissed. Returns a count and an items list
    # ordered most-recent-first; each item carries its surface, the failing
    # record, the run it belongs to (for a deep link), and a cause string.
    def self.failures(since:)
      dismissed = failure_dismissal_keys
      items = []

      Run.where(status: "failed").where("created_at >= ?", since).find_each do |run|
        next if dismissed.include?(["CompletionKit::Run", run.id])
        items << {
          surface: "run", record: run, run: run,
          cause: run.failure_summary.presence || "Run failed", at: run.updated_at
        }
      end

      Response.where(status: "failed").where("created_at >= ?", since)
              .includes(:run).find_each do |response|
        next if dismissed.include?(["CompletionKit::Response", response.id])
        items << {
          surface: "generation", record: response, run: response.run,
          cause: failure_cause(response), at: response.updated_at
        }
      end

      Review.where(status: "failed").where("completion_kit_reviews.created_at >= ?", since)
            .includes(response: :run).find_each do |review|
        next if dismissed.include?(["CompletionKit::Review", review.id])
        items << {
          surface: "judge", record: review, run: review.response.run,
          cause: failure_cause(review), at: review.updated_at
        }
      end

      items.sort_by! { |item| item[:at] }
      items.reverse!
      { count: items.size, items: items }
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

    def self.metric_dismissals
      DashboardDismissal.where(dismissable_type: "CompletionKit::Metric").index_by(&:dismissable_id)
    end
    private_class_method :metric_dismissals

    def self.failure_dismissal_keys
      DashboardDismissal.failures.map { |d| [d.dismissable_type, d.dismissable_id] }.to_set
    end
    private_class_method :failure_dismissal_keys

    def self.failure_cause(record)
      record.error_class.presence || "Unknown error"
    end
    private_class_method :failure_cause
  end
end
