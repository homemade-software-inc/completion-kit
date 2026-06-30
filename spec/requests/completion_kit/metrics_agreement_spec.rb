require "rails_helper"

RSpec.describe "CompletionKit metrics (agreement surfaces)", type: :request do
  let(:metric) { create(:completion_kit_metric, name: "Helpfulness") }
  let(:run) { create(:completion_kit_run, name: "Smoke run") }

  describe "GET metric show" do
    it "titles the card Agreement and uses no old label" do
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("Agreement")
      expect(response.body).not_to include(">Calibration<")
      expect(response.body).not_to include("This is a measure of how often the judge's scores match a human reviewer")
    end

    it "no longer renders a 'Cases to learn from' / few-shot section even when disagreements exist" do
      r1 = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: r1, metric: metric, metric_name: metric.name, metric_version_id: CompletionKit::MetricVersion.ensure_current_for(metric).id, ai_score: 5.0, ai_feedback: "judge said so")
      create(:completion_kit_agreement,
             run: run, response: r1, metric: metric,
             metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
             verdict: "disagree", corrected_score: 3.0, note: "off", created_by: SecureRandom.uuid)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Cases to learn from")
      expect(response.body).not_to include("Remember this")
    end

    it "points the review link at a current-version response, not a stale-version one" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      current_resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: current_resp, metric: metric, metric_name: metric.name, metric_version_id: v2.id, ai_score: 4.0, ai_feedback: "current")
      stale_resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, response: stale_resp, metric: metric, metric_name: metric.name, metric_version_id: v1.id, ai_score: 4.0, ai_feedback: "stale")

      get "/completion_kit/metrics/#{metric.id}"

      expect(response.body).to include("responses/#{current_resp.id}#helpfulness")
      expect(response.body).not_to include("responses/#{stale_resp.id}#helpfulness")
    end

    it "names the current version in the not-measured hint and notes earlier-version reviews below it" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      r = create(:completion_kit_response, run: run)
      create(:completion_kit_agreement, run: run, response: r, metric: metric,
             metric_version: v1, verdict: "agree", created_by: SecureRandom.uuid)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!

      get "/completion_kit/metrics/#{metric.id}"

      expect(response.body).to include("v2 needs")
      expect(response.body).to include("ck-trust-line__aside")
      expect(response.body).to include("from an earlier version")
      expect(response.body).not_to include("kept on file")
    end
  end

  describe "check metric show" do
    let(:check_metric) { create(:completion_kit_metric, :check) }

    it "hides the suggest/trust/guiding surfaces and shows a deterministic-check note" do
      get "/completion_kit/metrics/#{check_metric.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Agreement")
      expect(response.body).to include("nothing to calibrate")
      expect(response.body).not_to include("Suggest improvements")
      expect(response.body).not_to include("ck-trust-line")
    end

    it "still shows the trust panel for an llm-judge metric" do
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line")
    end

    it "does not query review-grounded examples for a check" do
      original = CompletionKit.config.judge_examples_from_reviews
      CompletionKit.config.judge_examples_from_reviews = true
      expect(CompletionKit::MetricAgreementExamples).not_to receive(:judge_examples_for)
      get "/completion_kit/metrics/#{check_metric.id}"
      expect(response).to have_http_status(:ok)
    ensure
      CompletionKit.config.judge_examples_from_reviews = original
    end
  end

  describe "trust panel borderline severity" do
    def add_borderline_agreements(n)
      n.times do
        r = create(:completion_kit_response, run: run)
        create(:completion_kit_agreement,
               run: run, response: r, metric: metric,
               metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
               verdict: "borderline", created_by: SecureRandom.uuid)
      end
    end

    def add_agree_agreements(n)
      n.times do
        r = create(:completion_kit_response, run: run)
        create(:completion_kit_agreement,
               run: run, response: r, metric: metric,
               metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
               verdict: "agree", created_by: SecureRandom.uuid)
      end
    end

    it "uses the warning level class when borderline rate is between 15% and 30%" do
      add_agree_agreements(8)
      add_borderline_agreements(2)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--warning")
    end

    it "uses the danger level class when borderline rate exceeds 30%" do
      add_agree_agreements(5)
      add_borderline_agreements(5)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--danger")
    end

    it "stays at the ok level when borderline rate is at or below 15%" do
      add_agree_agreements(14)
      add_borderline_agreements(1)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--ok")
    end
  end
end
