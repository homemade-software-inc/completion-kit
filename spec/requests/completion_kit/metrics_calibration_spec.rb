require "rails_helper"

RSpec.describe "CompletionKit metrics (calibration surfaces)", type: :request do
  let(:metric) { create(:completion_kit_metric, name: "Helpfulness") }
  let(:run) { create(:completion_kit_run, name: "Smoke run") }

  def add_review(response, ai_score:)
    create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: ai_score, ai_feedback: "judge said so")
  end

  def add_disagree_calibration(response, corrected:, note: "off by a star", created_by: SecureRandom.uuid)
    jv = CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_calibration,
           run: run, response: response, metric: metric,
           metric_version: jv, verdict: "disagree",
           corrected_score: corrected, note: note, created_by: created_by)
  end

  describe "GET metric show — disagreements section" do
    it "hides the disagreements section entirely when there are no disagreements yet" do
      get "/completion_kit/metrics/#{metric.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Cases to learn from")
    end

    it "lists disagreements with judge + human scores and an Add-as-few-shot button" do
      r1 = create(:completion_kit_response, run: run, row_index: 2)
      add_review(r1, ai_score: 5.0)
      add_disagree_calibration(r1, corrected: 3.0)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("Remember this")
      expect(response.body).to include("off by a star")
      expect(response.body).to include("View case 3 in")
      expect(response.body).to include("#" + metric.name.parameterize)
    end

    it "shows a 'Remembered' chip and hides the button once a disagreement has been pinned" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0)
      metric.update!(few_shot_examples: [{ "calibration_id" => cal.id }])
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-chip--done")
      expect(response.body).to include(">Remembered<")
      expect(response.body).not_to include('value="Remember this"')
    end

    it "hides the section when judge_calibration_enabled is off" do
      original = CompletionKit.config.judge_calibration_enabled
      CompletionKit.config.judge_calibration_enabled = false
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).not_to include("Cases to learn from")
    ensure
      CompletionKit.config.judge_calibration_enabled = original
    end
  end

  describe "POST add_few_shot" do
    it "appends the calibration's context to the metric's few_shot_examples and redirects with a flash" do
      r1 = create(:completion_kit_response, run: run, input_data: "Q: what is X?", response_text: "X is Y")
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0, note: "missed the nuance")
      post "/completion_kit/metrics/#{metric.id}/add_few_shot", params: { calibration_id: cal.id }
      expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
      follow_redirect!
      expect(response.body).to include("The judge will remember this")
      metric.reload
      expect(metric.few_shot_examples.size).to eq(1)
      example = metric.few_shot_examples.first
      expect(example["judge_score"]).to eq(5.0)
      expect(example["human_score"]).to eq(3.0)
      expect(example["human_note"]).to eq("missed the nuance")
      expect(example["calibration_id"]).to eq(cal.id)
    end

    it "404s when the calibration is not a disagree on this metric" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 4.0)
      agree = create(:completion_kit_calibration,
                     run: run, response: r1, metric: metric,
                     metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
                     verdict: "agree", created_by: "alice")
      expect {
        post "/completion_kit/metrics/#{metric.id}/add_few_shot", params: { calibration_id: agree.id }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "tolerates a disagree calibration whose review was deleted or whose scores were never populated" do
      r1 = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      cal = CompletionKit::Calibration.new(
        run: run, response: r1, metric: metric,
        metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
        verdict: "disagree", corrected_score: nil, note: nil, created_by: "ghost"
      )
      cal.save(validate: false)
      post "/completion_kit/metrics/#{metric.id}/add_few_shot", params: { calibration_id: cal.id }
      expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
      metric.reload
      example = metric.few_shot_examples.first
      expect(example["judge_score"]).to be_nil
      expect(example["human_score"]).to be_nil
      expect(example["judge_feedback"]).to eq("")
      expect(example["human_note"]).to eq("")
    end
  end

  describe "DELETE remove_few_shot" do
    it "drops the matching example from the metric's few_shot_examples and redirects with a flash" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0)
      r2 = create(:completion_kit_response, run: run)
      add_review(r2, ai_score: 4.0)
      cal_other = add_disagree_calibration(r2, corrected: 2.0)
      metric.update!(few_shot_examples: [
        { "calibration_id" => cal.id, "human_score" => 3.0 },
        { "calibration_id" => cal_other.id, "human_score" => 2.0 }
      ])
      delete "/completion_kit/metrics/#{metric.id}/remove_few_shot", params: { calibration_id: cal.id }
      expect(response).to redirect_to("/completion_kit/metrics/#{metric.id}")
      follow_redirect!
      expect(response.body).to include("Forgotten")
      metric.reload
      expect(metric.few_shot_examples.map { |fs| fs["calibration_id"] }).to eq([cal_other.id])
    end

    it "is a no-op when the calibration was never pinned" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0)
      metric.update!(few_shot_examples: [{ "calibration_id" => cal.id }])
      delete "/completion_kit/metrics/#{metric.id}/remove_few_shot", params: { calibration_id: 999_999 }
      metric.reload
      expect(metric.few_shot_examples.size).to eq(1)
    end
  end

  describe "metric show 'Cases to learn from'" do
    it "renders a Forget button on rows that have been pinned" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0)
      metric.update!(few_shot_examples: [{ "calibration_id" => cal.id }])
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include('value="Forget"')
      expect(response.body).to include("ck-disagreement--remembered")
    end

    it "no longer renders a separate 'What the judge remembers' card" do
      r1 = create(:completion_kit_response, run: run)
      add_review(r1, ai_score: 5.0)
      cal = add_disagree_calibration(r1, corrected: 3.0)
      metric.update!(few_shot_examples: [{ "calibration_id" => cal.id }])
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).not_to include("What the judge remembers")
    end
  end

  describe "trust panel borderline severity" do
    def add_borderline_calibrations(n)
      n.times do
        r = create(:completion_kit_response, run: run)
        create(:completion_kit_calibration,
               run: run, response: r, metric: metric,
               metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
               verdict: "borderline", created_by: SecureRandom.uuid)
      end
    end

    def add_agree_calibrations(n)
      n.times do
        r = create(:completion_kit_response, run: run)
        create(:completion_kit_calibration,
               run: run, response: r, metric: metric,
               metric_version: CompletionKit::MetricVersion.ensure_current_for(metric),
               verdict: "agree", created_by: SecureRandom.uuid)
      end
    end

    it "uses the warning level class when borderline rate is between 15% and 30%" do
      add_agree_calibrations(8)
      add_borderline_calibrations(2)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--warning")
    end

    it "uses the danger level class when borderline rate exceeds 30%" do
      add_agree_calibrations(5)
      add_borderline_calibrations(5)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--danger")
    end

    it "stays at the ok level when borderline rate is at or below 15%" do
      add_agree_calibrations(14)
      add_borderline_calibrations(1)
      get "/completion_kit/metrics/#{metric.id}"
      expect(response.body).to include("ck-trust-line__borderline--ok")
    end
  end
end
