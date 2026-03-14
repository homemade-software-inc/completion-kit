require "rails_helper"

RSpec.describe "Results and scoring", type: :model do
  let(:run) { create(:completion_kit_run) }
  let(:metric1) { create(:completion_kit_metric, name: "Relevance") }
  let(:metric2) { create(:completion_kit_metric, name: "Clarity") }

  let!(:r1) do
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: resp, metric: metric1, ai_score: 4.0, metric_name: "Relevance")
    create(:completion_kit_review, response: resp, metric: metric2, ai_score: 3.0, metric_name: "Clarity")
    resp
  end

  let!(:r2) do
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: resp, metric: metric1, ai_score: 5.0, metric_name: "Relevance")
    create(:completion_kit_review, response: resp, metric: metric2, ai_score: 2.0, metric_name: "Clarity")
    resp
  end

  describe "Response#score" do
    it "returns average of review scores" do
      expect(r1.score).to eq(3.5)
      expect(r2.score).to eq(3.5)
    end
  end

  describe "Response#reviewed?" do
    it "returns true when reviews with scores exist" do
      expect(r1.reviewed?).to be true
    end

    it "returns false with no reviews" do
      empty = create(:completion_kit_response, run: run)
      expect(empty.reviewed?).to be false
    end
  end

  describe "Run#avg_score" do
    it "returns average across all responses" do
      expect(run.avg_score).to eq(3.5)
    end
  end

  describe "Run#metric_averages" do
    it "returns per-metric averages" do
      avgs = run.metric_averages
      relevance = avgs.find { |m| m[:name] == "Relevance" }
      clarity = avgs.find { |m| m[:name] == "Clarity" }

      expect(relevance[:avg]).to eq(4.5)
      expect(clarity[:avg]).to eq(2.5)
    end
  end
end
