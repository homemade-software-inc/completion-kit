require "rails_helper"

RSpec.describe CompletionKit::TestResultMetricAssessment, type: :model do
  it "stores human review details and updates status" do
    assessment = create(:completion_kit_test_result_metric_assessment, human_score: nil, human_feedback: nil, human_reviewer_name: nil, human_reviewed_at: nil)

    assessment.apply_human_review!(reviewer_name: "Jamie", score: 7.5, feedback: "Solid")

    expect(assessment.reload.human_reviewer_name).to eq("Jamie")
    expect(assessment.human_score.to_f).to eq(7.5)
    expect(assessment.human_feedback).to eq("Solid")
    expect(assessment.human_reviewed_at).to be_present
    expect(assessment.status).to eq("reviewed")
  end

  it "keeps pending status when no ai score exists yet" do
    assessment = create(:completion_kit_test_result_metric_assessment, ai_score: nil, status: "pending")

    assessment.apply_human_review!(reviewer_name: "Jamie", score: 6.0, feedback: "Needs work")

    expect(assessment.reload.status).to eq("pending")
  end
end
