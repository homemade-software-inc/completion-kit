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

  it "raises a structured ProviderError when the LLM client returns an Error:-prefixed response" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).and_return("Error: 404 - model not found")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect { service.evaluate("actual") }.to raise_error(CompletionKit::ProviderError) do |error|
      expect(error.status).to eq(404)
      expect(error.message).to eq("model not found")
    end
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

  it "scopes the judge to the metric's dimension and tells it to ignore prompt rules unrelated to that dimension" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include(
        "Score strictly on the dimension",
        "Weigh it only when the dimension you are scoring is about adherence",
        "intrinsic quality",
        "do not lower the score for breaking it",
        "Original prompt: Summarize releases, never mention pricing",
        "Reminder: score only the dimension"
      ),
      model: "gpt-4.1"
    ).and_return("Score: 4\nFeedback: Scoped")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(
      service.evaluate("actual", "expected", "Summarize releases, never mention pricing", criteria: "Is every claim factually correct?")
    ).to eq(score: 4.0, feedback: "Scoped")
  end

  it "omits the prompt and its scoping guidance for judge-only runs with no prompt" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      satisfy { |p| !p.include?("Original prompt") && !p.include?("Weigh it only when the dimension") },
      model: "gpt-4.1"
    ).and_return("Score: 3\nFeedback: No prompt")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    expect(service.evaluate("actual", "expected", nil, criteria: "Quality?")).to eq(score: 3.0, feedback: "No prompt")
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

  it "injects human examples between the rubric and the output to evaluate, with and without a note" do
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion).with(
      include("Reviewed examples", "The judge scored this 4/5", "corrected it to 2/5", "way off", "corrected it to 5/5."),
      model: "gpt-4.1"
    ).and_return("Score: 2\nFeedback: Recalibrated")
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    service = described_class.new
    result = service.evaluate(
      "actual", nil, "prompt",
      human_examples: [
        { output: "some output", judge_score: 4.0, human_score: 2.0, human_note: "way off" },
        { output: "other output", judge_score: 1.0, human_score: 5.0, human_note: nil }
      ]
    )
    expect(result).to eq(score: 2.0, feedback: "Recalibrated")
  end

  it "produces a prompt with no examples block when human_examples is nil" do
    captured = nil
    client = instance_double(CompletionKit::OpenAiClient, configured?: true)
    allow(client).to receive(:generate_completion) do |prompt, **_|
      captured = prompt
      "Score: 3\nFeedback: fine"
    end
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

    described_class.new.evaluate("actual")
    expect(captured).not_to include("Reviewed examples")
  end
end
