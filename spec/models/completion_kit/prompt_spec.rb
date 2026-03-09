require "rails_helper"

RSpec.describe CompletionKit::Prompt, type: :model do
  it "exposes the available model list" do
    expect(described_class.available_models).to include(hash_including(id: "gpt-4.1"))
  end

  it "extracts variables from the template" do
    prompt = build(:completion_kit_prompt, template: "Hello {{ name }} and {{audience}}")

    expect(prompt.variables).to eq(%w[name audience])
  end

  it "supports current lookup, display helpers, cloning, publishing, and metric groups" do
    metric_group = create(:completion_kit_metric_group, :with_metrics)
    prompt = create(
      :completion_kit_prompt,
      name: "Family Prompt",
      family_key: "family-a",
      version_number: 1,
      metric_group: metric_group
    )

    expect(described_class.current_for("Family Prompt")).to eq(prompt)
    expect(described_class.current_for("family-a")).to eq(prompt)
    expect(prompt.version_label).to eq("v1")
    expect(prompt.display_name).to eq("Family Prompt v1")
    expect(prompt.assessment_metrics).to eq(metric_group.metrics.to_a)

    clone = prompt.clone_as_new_version(template: "Updated {{content}}", review_guidance: "Custom guidance")
    expect(clone.version_number).to eq(2)
    expect(clone.current).to eq(false)
    expect(clone.review_guidance).to eq("Custom guidance")
    expect(clone.metric_group).to eq(metric_group)

    clone.publish!
    expect(prompt.reload.current).to eq(false)
    expect(clone.reload.current).to eq(true)
  end

  it "falls back to a legacy metric when no metric group is attached" do
    prompt = create(:completion_kit_prompt, metric_group: nil)

    metric = prompt.assessment_metrics.first

    expect(prompt.assessment_metrics.length).to eq(1)
    expect(metric.name).to eq("Overall quality")
    expect(metric.persisted?).to eq(false)
    expect(metric.rubric_text).to include("9-10", "Reasoning cue:")
  end

  it "collects human review examples for a specific metric" do
    metric_group = create(:completion_kit_metric_group)
    metric = create(:completion_kit_metric)
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: metric)
    prompt = create(:completion_kit_prompt, family_key: "family-b", version_number: 1, metric_group: metric_group)
    test_run = create(:completion_kit_test_run, prompt: prompt)
    reviewed = create(:completion_kit_test_result, test_run: test_run, human_score: nil, human_feedback: nil, human_reviewed_at: nil)
    skipped = create(:completion_kit_test_result, test_run: test_run, human_score: nil, human_feedback: nil, human_reviewed_at: nil)
    create(:completion_kit_test_result_metric_assessment, test_result: reviewed, metric: metric, metric_name: metric.name, human_score: 8.0, human_feedback: "Good", human_reviewed_at: 1.hour.ago)
    create(:completion_kit_test_result_metric_assessment, test_result: skipped, metric: metric, metric_name: metric.name, human_score: 4.0, human_feedback: "Weak", human_reviewed_at: Time.current)

    examples = prompt.human_review_examples(metric: metric, excluding_test_result_id: skipped.id, limit: 5)

    expect(examples).to eq([{ input_data: reviewed.input_data, output_text: reviewed.output_text, human_score: 8.0, human_feedback: "Good" }])
  end

  it "returns no human review examples for non-persisted metrics" do
    prompt = create(:completion_kit_prompt, metric_group: nil)

    expect(prompt.human_review_examples(metric: prompt.assessment_metrics.first)).to eq([])
  end

  it "defaults current state and assessment model and parses legacy rubric text" do
    prompt = create(
      :completion_kit_prompt,
      current: nil,
      assessment_model: nil,
      metric_group: create(:completion_kit_metric_group),
      rubric_bands: nil,
      rubric_text: <<~RUBRIC
        9-10
        Criteria: Excellent
        Reasoning cue: Ready to ship
      RUBRIC
    )

    expect(prompt.current).to eq(true)
    expect(prompt.assessment_model).to eq(prompt.llm_model)
    expect(prompt.effective_rubric_bands.last["criteria"]).to eq("Excellent")
    expect(prompt.send(:parsed_rubric_bands_from_text, "")).to eq([])
  end

  it "returns human review examples without exclusion when requested" do
    metric_group = create(:completion_kit_metric_group)
    metric = create(:completion_kit_metric)
    create(:completion_kit_metric_group_membership, metric_group: metric_group, metric: metric)
    prompt = create(:completion_kit_prompt, metric_group: metric_group)
    test_run = create(:completion_kit_test_run, prompt: prompt)
    result = create(:completion_kit_test_result, test_run: test_run)
    create(:completion_kit_test_result_metric_assessment, test_result: result, metric: metric, metric_name: metric.name, human_score: 9.0, human_feedback: "Strong", human_reviewed_at: Time.current)

    expect(prompt.human_review_examples(metric: metric, limit: 5).first[:human_score]).to eq(9.0)
  end

  it "builds default rubric bands for prompts without a metric group and ignores invalid rubric chunks" do
    prompt = create(:completion_kit_prompt, metric_group: nil, rubric_bands: nil, rubric_text: nil)
    parsed = prompt.send(:parsed_rubric_bands_from_text, <<~RUBRIC)
       

      unknown
      Criteria: Ignore me
      Reasoning cue: Ignore me
    RUBRIC

    expect(prompt.rubric_bands.first["range"]).to eq("1-2")
    expect(parsed).to eq([])
  end
end
