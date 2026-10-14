require "rails_helper"

RSpec.describe CompletionKit::RunComparison do
  describe ".result_change" do
    it "is broke when a pass becomes a fail" do
      expect(described_class.result_change(true, false)).to eq("broke")
    end

    it "is fixed when a fail becomes a pass" do
      expect(described_class.result_change(false, true)).to eq("fixed")
    end

    it "is same when both sides agree" do
      expect(described_class.result_change(true, true)).to eq("same")
      expect(described_class.result_change(false, false)).to eq("same")
    end

    it "is nil when either side is unresolved" do
      expect(described_class.result_change(nil, false)).to be_nil
      expect(described_class.result_change(true, nil)).to be_nil
    end
  end

  describe ".score_delta" do
    it "is how far the right side moved from the left, to two places" do
      expect(described_class.score_delta(BigDecimal("0.5"), BigDecimal("0.8333"))).to eq(0.33)
      expect(described_class.score_delta(5, 3)).to eq(-2.0)
    end

    it "is nil when either side has no score" do
      expect(described_class.score_delta(nil, 0.5)).to be_nil
      expect(described_class.score_delta(0.5, nil)).to be_nil
    end
  end
end
