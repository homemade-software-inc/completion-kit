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

    it "returns true for a resolved check-only response (passed set, ai_score nil)" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: true)
      expect(resp.reviewed?).to be true
    end

    it "returns false when the only check is unresolved" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: nil, status: "pending")
      expect(resp.reviewed?).to be false
    end
  end

  describe "Response check counters" do
    it "counts resolved checks, passes, and failures and zeroes for a rubric-only response" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: true, metric_name: "A")
      create(:completion_kit_review, :check, response: resp, passed: false, metric_name: "B")
      create(:completion_kit_review, response: resp, ai_score: 4.0, metric_name: "Rubric")

      expect(resp.checks_total).to eq(2)
      expect(resp.checks_passed).to eq(1)
      expect(resp.checks_failed).to eq(1)
      expect(r1.checks_total).to eq(0)
    end
  end

  describe "Run#avg_score" do
    it "returns average across all responses" do
      expect(run.avg_score).to eq(3.5)
    end

    it "ignores check reviews (NULL ai_score never blends into the 1-5 average)" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: false)

      expect(run.avg_score).to eq(3.5)
      expect(r1.score).to eq(3.5)
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

    it "keeps {name, avg} for rubric metrics and adds a kind-tagged pass-rate entry for checks" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: true, metric_name: "Valid JSON")
      create(:completion_kit_review, :check, response: resp, passed: false, metric_name: "Valid JSON")

      avgs = run.metric_averages
      relevance = avgs.find { |m| m[:name] == "Relevance" }
      check = avgs.find { |m| m[:name] == "Valid JSON" }

      expect(relevance).to eq(name: "Relevance", avg: 4.5)
      expect(check[:kind]).to eq("check")
      expect(check[:pass_rate]).to eq(0.5)
    end

    it "omits a metric whose reviews are all unresolved" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: nil, status: "pending", metric_name: "Pending Check")

      expect(run.metric_averages.map { |m| m[:name] }).not_to include("Pending Check")
    end
  end

  describe "Run#check_pass_rate" do
    it "computes passed over resolved on a check run" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: true)
      create(:completion_kit_review, :check, response: resp, passed: false)

      expect(run.check_pass_rate).to eq(0.5)
    end

    it "returns nil when there are no resolved checks" do
      expect(run.check_pass_rate).to be_nil

      unresolved_run = create(:completion_kit_run)
      resp = create(:completion_kit_response, run: unresolved_run)
      create(:completion_kit_review, :check, response: resp, passed: nil, status: "pending")
      expect(unresolved_run.check_pass_rate).to be_nil
    end
  end
end
