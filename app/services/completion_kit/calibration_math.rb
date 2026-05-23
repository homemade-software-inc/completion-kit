module CompletionKit
  module CalibrationMath
    Z_95 = 1.959963984540054

    module_function

    def wilson_interval(successes:, n:, z: Z_95)
      return { point: nil, low: nil, high: nil } if n.to_i.zero?

      p_hat = successes.to_f / n
      denom = 1.0 + (z * z) / n
      center = (p_hat + (z * z) / (2.0 * n)) / denom
      margin = z * Math.sqrt((p_hat * (1 - p_hat) / n) + ((z * z) / (4.0 * n * n))) / denom

      { point: p_hat, low: [center - margin, 0.0].max, high: [center + margin, 1.0].min }
    end

    def mae(pairs)
      return nil if pairs.empty?
      sum = pairs.sum { |ai, human| (ai.to_f - human.to_f).abs }
      sum / pairs.length
    end

    def pearson(pairs)
      return nil if pairs.length < 2
      xs = pairs.map { |a, _| a.to_f }
      ys = pairs.map { |_, h| h.to_f }
      mx = xs.sum / xs.length
      my = ys.sum / ys.length
      num = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) }
      dx2 = xs.sum { |x| (x - mx)**2 }
      dy2 = ys.sum { |y| (y - my)**2 }
      denom = Math.sqrt(dx2 * dy2)
      return nil if denom.zero?
      num / denom
    end

    def quadratic_weighted_kappa(pairs, categories:)
      return nil if pairs.empty?

      ratings = categories.to_a
      k = ratings.length
      return nil if k < 2

      index = ratings.each_with_index.to_h
      observed = Array.new(k) { Array.new(k, 0) }
      row_totals = Array.new(k, 0)
      col_totals = Array.new(k, 0)
      n = 0

      pairs.each do |ai, human|
        i = index[score_bucket(ai, ratings)]
        j = index[score_bucket(human, ratings)]
        next if i.nil? || j.nil?
        observed[i][j] += 1
        row_totals[i] += 1
        col_totals[j] += 1
        n += 1
      end
      return nil if n.zero?

      max_dist_sq = (k - 1.0)**2
      numerator = 0.0
      denominator = 0.0
      (0...k).each do |i|
        (0...k).each do |j|
          weight = ((i - j)**2) / max_dist_sq
          expected = (row_totals[i] * col_totals[j]).to_f / n
          numerator   += weight * observed[i][j]
          denominator += weight * expected
        end
      end
      return 1.0 if denominator.zero?
      1.0 - (numerator / denominator)
    end

    def score_bucket(value, ratings)
      rounded = value.to_f.round
      return ratings.first if rounded <= ratings.first
      return ratings.last if rounded >= ratings.last
      rounded
    end
  end
end
