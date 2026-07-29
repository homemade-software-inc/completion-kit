module CompletionKit
  # Filtering, score-ordering and field projection for a run's responses,
  # shared by the REST endpoint and the MCP tool so both surfaces answer
  # "show me the worst rows, without the full bodies" the same way.
  class ResponseQuery
    SORTS = %w[id score_asc score_desc].freeze
    REVIEW_FIELD_PREFIX = "reviews.".freeze

    def initialize(run, status: nil, min_score: nil, max_score: nil, sort: nil, fields: nil)
      @run = run
      @status = status.presence
      @min_score = min_score.presence&.to_f
      @max_score = max_score.presence&.to_f
      @sort = SORTS.include?(sort.to_s) ? sort.to_s : "id"
      @fields = parse_fields(fields)
    end

    def relation
      return base.order(:id) unless score_scoped?

      ids = ordered_ids
      base.where(id: ids).in_order_of(:id, ids)
    end

    def serialize(response)
      project(response.as_json)
    end

    private

    def base
      scope = @run.responses.includes(:reviews)
      @status ? scope.where(status: @status) : scope
    end

    def score_scoped?
      filtering? || @sort != "id"
    end

    def filtering?
      !@min_score.nil? || !@max_score.nil?
    end

    def ordered_ids
      averages = score_averages
      scored, unscored = base.order(:id).pluck(:id).partition { |id| averages.key?(id) }
      kept = sort_by_score(scored.select { |id| in_range?(averages[id]) }, averages)
      filtering? ? kept : kept + unscored
    end

    # Mirrors Response#score (mean of the row's judge scores, rounded to 2) so a
    # min_score filter keeps exactly the rows whose reported score qualifies.
    def score_averages
      Review.where(response_id: base.select(:id))
            .where.not(ai_score: nil)
            .group(:response_id)
            .pluck(:response_id, Arel.sql("AVG(ai_score)"))
            .to_h { |id, avg| [id, avg.to_f.round(2)] }
    end

    def in_range?(average)
      return false if @min_score && average < @min_score
      return false if @max_score && average > @max_score

      true
    end

    def sort_by_score(ids, averages)
      return ids if @sort == "id"

      sorted = ids.sort_by { |id| averages[id] }
      @sort == "score_desc" ? sorted.reverse : sorted
    end

    def parse_fields(raw)
      names = Array(raw).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:empty?)
      {
        top: names.reject { |name| name.start_with?(REVIEW_FIELD_PREFIX) }.map(&:to_sym),
        reviews: names.select { |name| name.start_with?(REVIEW_FIELD_PREFIX) }
                      .map { |name| name.delete_prefix(REVIEW_FIELD_PREFIX).to_sym }
      }
    end

    def project(json)
      return json if @fields[:top].empty? && @fields[:reviews].empty?

      projected = json.slice(:id, *@fields[:top])
      if @fields[:reviews].any?
        projected[:reviews] = json[:reviews].map { |review| review.slice(*@fields[:reviews]) }
      end
      projected
    end
  end
end
