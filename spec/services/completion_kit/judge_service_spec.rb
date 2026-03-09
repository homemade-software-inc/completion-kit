require "rails_helper"

RSpec.describe CompletionKit::JudgeService, type: :service do
  around do |example|
    original_model = CompletionKit.config.judge_model
    CompletionKit.config.judge_model = "gpt-4.1"
    example.run
  ensure
    CompletionKit.config.judge_model = original_model
  end

  it "returns a zero score when the judge client is not configured" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: false)

    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("output")).to eq(score: 0, feedback: "Judge not configured")
  end

  it "builds prompts with expected output and parses the judge response" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)

    allow(client).to receive(:generate_completion).with(include("Expected output:", "Structured rubric:", "Reasoning cue:"), model: "gpt-4.1").and_return("Score: 8.8\nFeedback: Strong match")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual", "expected", "prompt")).to eq(score: 8.8, feedback: "Strong match")
  end

  it "builds prompts without expected output and clamps invalid scores" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)

    allow(client).to receive(:generate_completion).with(include("Input data for this result:", "Not provided"), model: "gpt-4.1").and_return("Score: 120\nFeedback: Great")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 10, feedback: "Great")
  end

  it "returns a default response when parsing finds no markers" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)

    allow(client).to receive(:generate_completion).and_return("No structure")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 0, feedback: "No feedback provided")
  end

  it "returns an error response when the judge client raises" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)

    allow(client).to receive(:generate_completion).and_raise(StandardError, "judge timeout")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual")).to eq(score: 0, feedback: "Error during evaluation: judge timeout")
  end

  it "includes custom guidance, rubric text, and human examples when provided" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)

    allow(client).to receive(:generate_completion).with(
      include("Assessment guidance:", "Use the support rubric", "Human-reviewed calibration examples:", "Human score: 9.5", "Custom rubric text"),
      model: "gpt-4.1"
    ).and_return("Score: 7.2\nFeedback: Calibrated")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(
      service.evaluate(
        "actual",
        "expected",
        "prompt",
        review_guidance: "Use the support rubric",
        rubric_text: "Custom rubric text",
        human_examples: [{ input_data: "{x:1}", output_text: "draft", human_score: 9.5, human_feedback: "Excellent" }]
      )
    ).to eq(score: 7.2, feedback: "Calibrated")
  end
end
