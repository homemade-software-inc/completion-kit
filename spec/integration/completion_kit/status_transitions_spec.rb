require "rails_helper"
require "faraday"

RSpec.describe "Run status transitions", type: :model do
  let(:prompt) { create(:completion_kit_prompt, llm_model: "gpt-4.1") }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")

    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
      original.call(*args, **kwargs) do |builder|
        builder.adapter :test, stubs
      end
    end
  end

  it "pending -> generating -> completed (no judge)" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No judge")

    stubs.post("/v1/chat/completions") do
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: "output" } }]
      }.to_json]
    end

    run.generate_responses!
    expect(run.reload.status).to eq("completed")
  end

  it "pending -> generating -> judging -> completed (with judge)" do
    metric = create(:completion_kit_metric)
    criteria = create(:completion_kit_criteria)
    CompletionKit::CriteriaMembership.create!(criteria: criteria, metric: metric, position: 1)

    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "With judge",
      judge_model: "gpt-4.1", criteria: criteria
    )

    call_count = 0
    stubs.post("/v1/chat/completions") do
      call_count += 1
      content = if call_count == 1
                  "Generated output"
                else
                  "Score: 4\nFeedback: Good"
                end
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: content } }]
      }.to_json]
    end

    run.generate_responses!
    expect(run.reload.status).to eq("completed")
    expect(run.responses.first.reviews.count).to eq(1)
  end

  it "sets status to failed on generation error" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "Fail test")

    stubs.post("/v1/chat/completions") do
      raise Faraday::ConnectionFailed, "Connection refused"
    end

    result = run.generate_responses!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end

  it "sets status to failed on judging error" do
    metric = create(:completion_kit_metric)
    criteria = create(:completion_kit_criteria)
    CompletionKit::CriteriaMembership.create!(criteria: criteria, metric: metric, position: 1)

    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge fail",
      judge_model: "gpt-4.1", criteria: criteria, status: "completed"
    )
    run.responses.create!(input_data: nil, response_text: "Some output")

    stubs.post("/v1/chat/completions") do
      raise Faraday::ConnectionFailed, "Connection refused"
    end

    result = run.judge_responses!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end
end
