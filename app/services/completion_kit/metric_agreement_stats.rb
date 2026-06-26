module CompletionKit
  class MetricAgreementStats
    PROVISIONAL_MIN = 10
    FIRM_MIN = 30

    Result = Struct.new(
      :sample_size, :agree_count, :disagree_count, :borderline_count,
      :agreement_point, :agreement_low, :agreement_high,
      :borderline_rate, :mae, :pearson, :kappa, :gate,
      keyword_init: true
    ) do
      def counter_only?
        gate == :counter
      end

      def provisional?
        gate == :provisional
      end

      def firm?
        gate == :firm
      end

      def short_to_target
        [PROVISIONAL_MIN - sample_size, 0].max
      end

      def margin
        return nil if agreement_low.nil? || agreement_high.nil?
        (agreement_high - agreement_low) / 2.0
      end
    end

    CURRENT = :current

    def self.for(metric, metric_version: CURRENT)
      resolved = case metric_version
                 when CURRENT then MetricVersion.current.find_by(metric_id: metric.id)
                 when nil then nil
                 else metric_version
                 end
      new(metric: metric, metric_version: resolved, all_versions: metric_version.nil?).call
    end

    def initialize(metric:, metric_version: nil, all_versions: false)
      @metric = metric
      @metric_version = metric_version
      @all_versions = all_versions
    end

    def call
      scope = Agreement.where(metric_id: @metric.id, run_id: Run.visible_run_ids)
      if @metric_version
        scope = scope.where(metric_version_id: @metric_version.id)
      elsif !@all_versions
        scope = scope.none
      end

      verdicts = scope.pluck(:verdict, :corrected_score, :response_id)
      n = verdicts.length
      agrees = verdicts.count { |v, _, _| v == "agree" }
      disagrees = verdicts.count { |v, _, _| v == "disagree" }
      borderlines = verdicts.count { |v, _, _| v == "borderline" }

      ci = AgreementMath.wilson_interval(successes: agrees, n: n)

      pairs = score_pairs(verdicts)
      mae_value = AgreementMath.mae(pairs)
      pearson_value = AgreementMath.pearson(pairs)
      kappa_value = AgreementMath.quadratic_weighted_kappa(pairs, categories: 1..5)

      Result.new(
        sample_size: n,
        agree_count: agrees,
        disagree_count: disagrees,
        borderline_count: borderlines,
        agreement_point: ci[:point],
        agreement_low: ci[:low],
        agreement_high: ci[:high],
        borderline_rate: n.zero? ? nil : borderlines.to_f / n,
        mae: mae_value,
        pearson: pearson_value,
        kappa: kappa_value,
        gate: gate_for(n)
      )
    end

    private

    def score_pairs(verdicts)
      response_ids = verdicts.map { |_, _, rid| rid }.uniq
      ai_scores = Review.where(response_id: response_ids, metric_id: @metric.id)
                       .pluck(:response_id, :ai_score).to_h

      verdicts.filter_map do |verdict, corrected, response_id|
        next if verdict == "borderline"
        ai = ai_scores[response_id]
        next if ai.nil?
        human = verdict == "agree" ? ai : corrected
        next if human.nil?
        [ai.to_f, human.to_f]
      end
    end

    def gate_for(n)
      return :counter if n < PROVISIONAL_MIN
      return :firm if n >= FIRM_MIN
      :provisional
    end
  end
end
