require "rails_helper"
require "faraday"

RSpec.describe "End-to-end judging pipeline", type: :model do
  let(:metric) do
    create(:completion_kit_metric, name: "Relevance", instruction: "Is the output relevant?")
  end
  let(:prompt) do
    create(:completion_kit_prompt, template: "Summarize {{content}}", llm_model: "gpt-4.1")
  end
  let(:run) do
    r = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge test",
      judge_model: "gpt-4.1", status: "completed"
    )
    CompletionKit::RunMetric.create!(run: r, metric: metric, position: 1)
    r.responses.create!(input_data: nil, response_text: "A good summary")
    r
  end

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)

    stubs.post("/v1/responses") do
      [200, { "Content-Type" => "application/json" }, {
        output: [{ type: "message", content: [{ type: "output_text", text: "Score: 4\nFeedback: Relevant and well-structured." }] }]
      }.to_json]
    end

    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
      original.call(*args, **kwargs) do |builder|
        builder.adapter :test, stubs
      end
    end
  end

  it "creates reviews with scores and feedback, transitions to completed" do
    expect(run.status).to eq("completed")

    run.judge_responses!

    expect(run.reload.status).to eq("completed")

    response = run.responses.first
    expect(response.reviews.count).to eq(1)

    review = response.reviews.first
    expect(review.ai_score).to eq(4.0)
    expect(review.ai_feedback).to include("Relevant")
    expect(review.metric_id).to eq(metric.id)
    expect(review.metric_name).to eq("Relevance")
    expect(review.status).to eq("evaluated")
  end

  it "updates existing reviews on re-judge without duplicating" do
    run.judge_responses!
    expect(run.responses.first.reviews.count).to eq(1)

    stubs.post("/v1/responses") do
      [200, { "Content-Type" => "application/json" }, {
        output: [{ type: "message", content: [{ type: "output_text", text: "Score: 5\nFeedback: Excellent work." }] }]
      }.to_json]
    end

    run.judge_responses!

    response = run.responses.first
    expect(response.reviews.count).to eq(1)
    expect(response.reviews.first.ai_score).to eq(5.0)
    expect(response.reviews.first.ai_feedback).to include("Excellent")
  end
end
