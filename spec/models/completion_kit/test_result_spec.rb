require "rails_helper"

RSpec.describe CompletionKit::TestResult, type: :model do
  describe "#evaluate_quality" do
    it "persists per-metric assessments and aggregate score" do
      metric_group = create(:completion_kit_metric_group, :with_metrics, metrics_count: 2)
      test_result = create(:completion_kit_test_result, test_run: create(:completion_kit_test_run, prompt: create(:completion_kit_prompt, metric_group: metric_group)), quality_score: nil, judge_feedback: nil, status: "completed")
      judge = instance_double(CompletionKit::JudgeService)

      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)
      allow(judge).to receive(:evaluate).and_return({ score: 9.0, feedback: "Strong match" }, { score: 7.0, feedback: "Good enough" })

      expect(test_result.evaluate_quality).to eq(true)
      expect(test_result.reload.quality_score.to_f).to eq(8.0)
      expect(test_result.judge_feedback).to include("Strong match", "Good enough")
      expect(test_result.status).to eq("evaluated")
      expect(test_result.metric_assessments.count).to eq(2)
    end

    it "supports the legacy single-metric fallback and preserves human review status on reevaluation" do
      test_result = create(:completion_kit_test_result, test_run: create(:completion_kit_test_run, prompt: create(:completion_kit_prompt, metric_group: nil)), quality_score: nil, judge_feedback: nil)
      judge = instance_double(CompletionKit::JudgeService, evaluate: { score: 8.0, feedback: "Legacy metric" })

      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)

      expect(test_result.evaluate_quality).to eq(true)
      assessment = test_result.reload.metric_assessments.first
      assessment.apply_human_review!(reviewer_name: "Dana", score: 8.5, feedback: "Looks right")

      expect(test_result.evaluate_quality).to eq(true)
      expect(test_result.reload.metric_assessments.first.status).to eq("reviewed")
      expect(test_result.metric_assessments.first.metric_id).to be_nil
    end

    it "returns false without output text" do
      test_result = build(:completion_kit_test_result, output_text: "")

      expect(test_result.evaluate_quality).to eq(false)
    end

    it "captures evaluation failures" do
      test_result = create(:completion_kit_test_result)
      judge = instance_double(CompletionKit::JudgeService)

      allow(judge).to receive(:evaluate).and_raise(StandardError, "judge down")
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)

      expect(test_result.evaluate_quality).to eq(false)
      expect(test_result.reload.status).to eq("failed")
      expect(test_result.judge_feedback).to include("judge down")
    end

    it "returns false when no assessment metrics are available" do
      test_result = create(:completion_kit_test_result)

      allow(test_result.prompt).to receive(:assessment_metrics).and_return([])

      expect(test_result.evaluate_quality).to eq(false)
    end
  end

  describe "#quality_band" do
    it "uses configured thresholds" do
      test_result = build(:completion_kit_test_result, quality_score: 6.5)

      expect(test_result.quality_band).to eq(:medium)
    end

    it "returns the remaining quality bands" do
      expect(build(:completion_kit_test_result, quality_score: 9.0).quality_band).to eq(:high)
      expect(build(:completion_kit_test_result, quality_score: 1.0).quality_band).to eq(:low)
      expect(build(:completion_kit_test_result, quality_score: nil).quality_band).to eq(:pending)
    end
  end

  describe "#metric_assessments_for_review" do
    it "builds assessments from prompt metrics when none exist" do
      metric_group = create(:completion_kit_metric_group, :with_metrics)
      test_result = create(:completion_kit_test_result, test_run: create(:completion_kit_test_run, prompt: create(:completion_kit_prompt, metric_group: metric_group)))

      expect(test_result.metric_assessments_for_review.map(&:metric_name)).to eq(metric_group.metrics.pluck(:name))
    end

    it "builds review assessments for the legacy fallback metric" do
      test_result = create(:completion_kit_test_result, test_run: create(:completion_kit_test_run, prompt: create(:completion_kit_prompt, metric_group: nil)))

      expect(test_result.metric_assessments_for_review.first.metric).to be_nil
      expect(test_result.metric_assessments_for_review.first.metric_name).to eq("Overall quality")
    end
  end

  describe "#apply_human_reviews!" do
    it "stores per-metric reviewer details and updates aggregate scores" do
      assessment = create(:completion_kit_test_result_metric_assessment, human_score: nil, human_feedback: nil, human_reviewer_name: nil, human_reviewed_at: nil)
      test_result = assessment.test_result

      test_result.apply_human_reviews!(
        [{ id: assessment.id, metric_name: assessment.metric_name, human_reviewer_name: "Jamie", human_score: 7.0, human_feedback: "Solid but incomplete" }]
      )

      expect(assessment.reload.human_reviewer_name).to eq("Jamie")
      expect(assessment.human_score.to_f).to eq(7.0)
      expect(assessment.human_feedback).to eq("Solid but incomplete")
      expect(assessment.human_reviewed_at).to be_present
      expect(test_result.reload.human_score.to_f).to eq(7.0)
    end

    it "finds assessments by metric id or metric name and tolerates blank submissions" do
      metric = create(:completion_kit_metric)
      test_result = create(:completion_kit_test_result)

      test_result.apply_human_reviews!(
        [
          { metric_id: metric.id, metric_name: metric.name, guidance_text: metric.guidance_text, rubric_text: metric.rubric_text, human_reviewer_name: "Dana", human_score: 6.0, human_feedback: "Needs edits" },
          { metric_name: "Legacy", guidance_text: "", rubric_text: "Legacy rubric", human_reviewer_name: "Dana", human_score: 5.0, human_feedback: "Fallback path" },
          { metric_name: "Skipped", human_reviewer_name: "", human_score: "", human_feedback: "" }
        ]
      )

      expect(test_result.metric_assessments.find_by(metric_id: metric.id).human_score.to_f).to eq(6.0)
      expect(test_result.metric_assessments.find_by(metric_name: "Legacy").human_feedback).to eq("Fallback path")
    end
  end
end
