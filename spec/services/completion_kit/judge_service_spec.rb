require "rails_helper"

RSpec.describe CompletionKit::JudgeService, type: :service do
  around do |example|
    original_model = CompletionKit.config.judge_model
    CompletionKit.config.judge_model = "gpt-4.1"
    example.run
  ensure
    CompletionKit.config.judge_model = original_model
  end

  it "raises ConfigurationError when the judge client is not configured" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: false)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("output") }.to raise_error(CompletionKit::ConfigurationError, /Judge not configured/)
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

  it "raises JudgeParseError when the response has no score" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("I cannot evaluate this")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("actual") }.to raise_error(CompletionKit::JudgeParseError, /Could not parse judge response/)
  end

  it "raises when the LLM client returns an Error:-prefixed response" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("Error: 404 - model not found")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("actual") }.to raise_error(StandardError, /Error: 404/)
  end

  it "re-raises any StandardError the judge client raises" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_raise(StandardError, "judge timeout")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("actual") }.to raise_error(StandardError, "judge timeout")
  end

  it "re-raises Faraday::Error from the judge client" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_raise(Faraday::ConnectionFailed, "connection refused")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("actual") }.to raise_error(Faraday::ConnectionFailed)
  end

  it "includes criteria and rubric text in prompt" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("Criteria:", "Check for accuracy", "Custom rubric"),
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
        rubric_text: "Custom rubric"
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
