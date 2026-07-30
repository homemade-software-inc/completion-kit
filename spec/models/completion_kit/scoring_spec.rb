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

    it "reports how many rows each metric graded and how many scored low" do
      avgs = run.metric_averages

      expect(avgs.find { |m| m[:name] == "Relevance" }).to eq(name: "Relevance", avg: 4.5, count: 2, low_count: 0)
      expect(avgs.find { |m| m[:name] == "Clarity" }).to eq(name: "Clarity", avg: 2.5, count: 2, low_count: 1)
    end

    it "follows the configured medium quality threshold when counting low scores" do
      CompletionKit.config.medium_quality_threshold = 5
      expect(run.metric_averages.find { |m| m[:name] == "Relevance" }[:low_count]).to eq(1)
    ensure
      CompletionKit.instance_variable_set(:@config, nil)
    end

    it "keeps {name, avg} for rubric metrics and adds a kind-tagged pass-rate entry for checks" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: true, metric_name: "Valid JSON")
      create(:completion_kit_review, :check, response: resp, passed: false, metric_name: "Valid JSON")

      avgs = run.metric_averages
      relevance = avgs.find { |m| m[:name] == "Relevance" }
      check = avgs.find { |m| m[:name] == "Valid JSON" }

      expect(relevance).to eq(name: "Relevance", avg: 4.5, count: 2, low_count: 0)
      expect(check).to eq(name: "Valid JSON", kind: "check", pass_rate: 0.5, count: 2, low_count: 1)
    end

    it "omits a metric whose reviews are all unresolved" do
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, passed: nil, status: "pending", metric_name: "Pending Check")

      expect(run.metric_averages.map { |m| m[:name] }).not_to include("Pending Check")
    end
  end

  describe "Run#scores_at_ceiling?" do
    let(:ceiling_run) { create(:completion_kit_run, status: "completed") }

    def score_rows(scores)
      scores.each do |score|
        resp = create(:completion_kit_response, run: ceiling_run)
        create(:completion_kit_review, response: resp, metric: metric1, metric_name: "Relevance", ai_score: score)
      end
      CompletionKit::Run.find(ceiling_run.id)
    end

    it "flags a near-max average" do
      expect(score_rows([5.0] * 9 + [4.0]).scores_at_ceiling?).to be(true)
    end

    it "flags nearly every score landing on the top band even when the mean is lower" do
      run = score_rows([5.0] * 18 + [1.0, 1.0])
      expect(run.avg_score).to be < CompletionKit::Run::CEILING_MEAN
      expect(run.scores_at_ceiling?).to be(true)
    end

    it "stays quiet on a discriminating judge" do
      expect(score_rows([5.0, 4.0, 3.0, 2.0, 1.0] * 2).scores_at_ceiling?).to be(false)
    end

    it "stays quiet below the sample-size floor, however perfect the scores" do
      expect(score_rows([5.0] * 9).scores_at_ceiling?).to be(false)
    end

    it "stays quiet until the run has completed" do
      ceiling_run.update_columns(status: "running")
      expect(score_rows([5.0] * 12).scores_at_ceiling?).to be(false)
    end

    it "stays quiet on a check-only run where no judge score exists" do
      12.times do
        resp = create(:completion_kit_response, run: ceiling_run)
        create(:completion_kit_review, :check, response: resp, passed: true)
      end
      expect(CompletionKit::Run.find(ceiling_run.id).scores_at_ceiling?).to be(false)
    end
  end

  describe "Run#calibratable_metric" do
    it "returns a judge metric and never a check" do
      run = create(:completion_kit_run)
      check = create(:completion_kit_metric, :check)
      judge = create(:completion_kit_metric)
      run.replace_metrics!([check.id, judge.id])

      expect(run.reload.calibratable_metric).to eq(judge)
    end

    it "returns nil when the run only has checks" do
      run = create(:completion_kit_run)
      run.replace_metrics!([create(:completion_kit_metric, :check).id])

      expect(run.reload.calibratable_metric).to be_nil
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
