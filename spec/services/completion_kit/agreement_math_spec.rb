require "rails_helper"

RSpec.describe CompletionKit::AgreementMath do
  describe ".wilson_interval" do
    it "returns nil triples when n is zero" do
      expect(described_class.wilson_interval(successes: 0, n: 0)).to eq(point: nil, low: nil, high: nil)
    end

    it "centers near the point estimate with a wide margin at small n" do
      result = described_class.wilson_interval(successes: 8, n: 10)
      expect(result[:point]).to eq(0.8)
      expect(result[:low]).to be < 0.8
      expect(result[:high]).to be > 0.8
      expect(result[:high] - result[:low]).to be > 0.3
    end

    it "tightens the margin as n grows" do
      tight = described_class.wilson_interval(successes: 80, n: 100)
      wide = described_class.wilson_interval(successes: 8, n: 10)
      tight_margin = tight[:high] - tight[:low]
      wide_margin = wide[:high] - wide[:low]
      expect(tight_margin).to be < wide_margin
    end

    it "tops out near 1.0 for perfect agreement (clamped)" do
      result = described_class.wilson_interval(successes: 10, n: 10)
      expect(result[:high]).to be_within(1e-6).of(1.0)
      expect(result[:low]).to be < 1.0
    end

    it "bottoms out near 0.0 for zero successes (clamped)" do
      result = described_class.wilson_interval(successes: 0, n: 10)
      expect(result[:low]).to be_within(1e-6).of(0.0)
      expect(result[:high]).to be > 0.0
    end

    it "clamps explicitly when float overshoot would otherwise push past the bounds" do
      stub = instance_double(Float)
      expect(described_class.wilson_interval(successes: 100, n: 100)[:high]).to be <= 1.0
      expect(described_class.wilson_interval(successes: 0, n: 100)[:low]).to be >= 0.0
    end
  end

  describe ".mae" do
    it "is nil for an empty set" do
      expect(described_class.mae([])).to be_nil
    end

    it "averages absolute error" do
      expect(described_class.mae([[5, 3], [4, 4], [2, 1]])).to be_within(0.0001).of(1.0)
    end
  end

  describe ".pearson" do
    it "is nil when there are fewer than two pairs" do
      expect(described_class.pearson([])).to be_nil
      expect(described_class.pearson([[1, 2]])).to be_nil
    end

    it "returns nil when one variable has no variance (divide by zero)" do
      expect(described_class.pearson([[3, 1], [3, 2], [3, 5]])).to be_nil
    end

    it "is 1.0 for perfectly correlated input" do
      pairs = [[1, 2], [2, 4], [3, 6], [4, 8]]
      expect(described_class.pearson(pairs)).to be_within(0.0001).of(1.0)
    end

    it "is negative for anti-correlated input" do
      pairs = [[1, 5], [2, 4], [3, 3], [4, 2], [5, 1]]
      expect(described_class.pearson(pairs)).to be < 0
    end
  end

  describe ".quadratic_weighted_kappa" do
    it "is nil for empty input" do
      expect(described_class.quadratic_weighted_kappa([], categories: 1..5)).to be_nil
    end

    it "is nil when categories are degenerate" do
      expect(described_class.quadratic_weighted_kappa([[1, 1]], categories: [1])).to be_nil
    end

    it "is 1.0 when every pair is identical (perfect agreement collapses to no-disagreement)" do
      pairs = Array.new(10) { [3, 3] }
      expect(described_class.quadratic_weighted_kappa(pairs, categories: 1..5)).to eq(1.0)
    end

    it "drops below 1.0 when raters disagree at the edges" do
      pairs = [[5, 1], [5, 1], [5, 1], [1, 5]]
      result = described_class.quadratic_weighted_kappa(pairs, categories: 1..5)
      expect(result).to be < 0.5
    end

    it "buckets out-of-range scores to the nearest endpoint" do
      pairs = [[0.2, 1.1], [6.5, 4.8]]
      expect { described_class.quadratic_weighted_kappa(pairs, categories: 1..5) }.not_to raise_error
    end

    it "skips a pair whose buckets fall outside the supplied categories" do
      expect(described_class.score_bucket(2.4, [1, 2, 3, 4, 5])).to eq(2)
      expect(described_class.score_bucket(2.6, [1, 2, 3, 4, 5])).to eq(3)
      mixed = [[2, 2], [2, 2], [2, 2], [2, 2], [2, 2]]
      expect(described_class.quadratic_weighted_kappa(mixed, categories: 1..5)).to eq(1.0)
    end

    it "returns nil when non-contiguous categories cause every pair's bucket lookup to miss" do
      result = described_class.quadratic_weighted_kappa([[2, 4], [2, 4]], categories: [1, 3, 5])
      expect(result).to be_nil
    end
  end
end
