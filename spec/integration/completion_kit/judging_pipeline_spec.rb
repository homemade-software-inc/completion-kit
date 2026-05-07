require "rails_helper"

RSpec.describe "End-to-end judging pipeline", type: :model do
  let(:metric) do
    create(:completion_kit_metric, name: "Relevance", instruction: "Is the output relevant?")
  end
  let(:prompt) do
    create(:completion_kit_prompt, template: "Summarize the latest update", llm_model: "gpt-4.1")
  end

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
  end

  it "outstanding_work_zero? returns true after all reviews are terminal" do
    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge test",
      judge_model: "gpt-4.1", status: "running"
    )
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    response = run.responses.create!(status: "succeeded", response_text: "done")
    response.reviews.create!(metric: metric, status: "succeeded", metric_name: metric.name)

    expect(run.outstanding_work_zero?).to be true
  end

  it "outstanding_work_zero? returns false while reviews are pending" do
    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge test",
      judge_model: "gpt-4.1", status: "running"
    )
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    response = run.responses.create!(status: "succeeded", response_text: "done")
    response.reviews.create!(metric: metric, status: "pending", metric_name: metric.name)

    expect(run.outstanding_work_zero?).to be false
  end
end
