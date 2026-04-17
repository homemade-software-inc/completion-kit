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

  it "returns score with no-feedback message when only score is present" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("Score: 3")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 3.0, feedback: "No feedback provided")
  end

  it "returns parse error when response has no score or feedback" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("I cannot evaluate this")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    result = service.evaluate("actual")
    expect(result[:score]).to eq(1)
    expect(result[:feedback]).to include("Could not parse judge response")
  end

  it "raises when LLM returns an Error: prefixed response" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("Error: 404 - model not found")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    result = service.evaluate("actual")
    expect(result[:score]).to eq(1)
    expect(result[:feedback]).to include("Error: 404")
  end

  it "returns an error response when the judge client raises" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_raise(StandardError, "judge timeout")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 1, feedback: "Error during evaluation: judge timeout")
  end

  it "includes criteria, rubric text, and human examples in prompt" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("Criteria:", "Check for accuracy", "Custom rubric", "Calibration examples:", "score=4"),
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
        rubric_text: "Custom rubric",
        human_examples: [{ input_data: "{x:1}", response_text: "draft", human_score: 4, human_feedback: "Good" }]
      )
    ).to eq(score: 3.0, feedback: "Calibrated")
  end

  it "includes input_data in the judge prompt when provided" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion)
      .with(include("Input data: {customer: acme}"), model: "gpt-4.1")
      .and_return("Score: 5\nFeedback: Accurate")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual", nil, "prompt", input_data: "{customer: acme}"))
      .to eq(score: 5.0, feedback: "Accurate")
  end
end
