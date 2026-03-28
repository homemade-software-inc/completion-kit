require "rails_helper"

RSpec.describe CompletionKit::JudgeService, type: :service do
  around do |example|
    original_model = CompletionKit.config.judge_model
    CompletionKit.config.judge_model = "gpt-4.1"
    example.run
  ensure
    CompletionKit.config.judge_model = original_model
  end

  it "returns score 1 when the judge client is not configured" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: false)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("output")).to eq(score: 1, feedback: "Judge not configured")
  end

  it "parses score and feedback from judge response" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("1 to 5", "AI output to evaluate:"),
      model: "gpt-4.1"
    ).and_return("Score: 4\nFeedback: Strong match")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual", "expected", "prompt")).to eq(score: 4.0, feedback: "Strong match")
  end

  it "clamps scores to 1-5 range" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("Score: 120\nFeedback: Great")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 5, feedback: "Great")
  end

  it "returns an error response when the judge client raises" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_raise(StandardError, "judge timeout")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 1, feedback: "Error during evaluation: judge timeout")
  end

  it "includes criteria, evaluation steps, rubric text, and human examples in prompt" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("Criteria:", "Check for accuracy", "Evaluation steps:", "Step one", "Custom rubric", "Calibration examples:", "score=4"),
      model: "gpt-4.1"
    ).and_return("Score: 3\nFeedback: Calibrated")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(
      service.evaluate(
        "actual",
        "expected",
        "prompt",
        criteria: "Check for accuracy",
        evaluation_steps: ["Step one"],
        rubric_text: "Custom rubric",
        human_examples: [{ input_data: "{x:1}", response_text: "draft", human_score: 4, human_feedback: "Good" }]
      )
    ).to eq(score: 3.0, feedback: "Calibrated")
  end
end
