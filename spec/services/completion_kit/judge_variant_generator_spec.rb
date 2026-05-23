require "rails_helper"

RSpec.describe CompletionKit::JudgeVariantGenerator, type: :service do
  let(:metric) { create(:completion_kit_metric, instruction: "Be fair") }

  def stub_llm(response_text)
    client = instance_double("CompletionKit::OpenAiClient")
    allow(client).to receive(:generate_completion).and_return(response_text)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
  end

  describe "#call" do
    it "parses well-formed VARIANT blocks into Variant structs" do
      stub_llm(<<~OUT)
        VARIANT:
        REASONING: tighter focus on factuality
        INSTRUCTION:
        Be fair and reward factual accuracy first.
        END_VARIANT

        VARIANT:
        REASONING: brevity bonus
        INSTRUCTION:
        Be fair, also penalize verbose answers.
        END_VARIANT
      OUT

      variants = described_class.new(metric, count: 3).call
      expect(variants.length).to eq(2)
      expect(variants.first.reasoning).to eq("tighter focus on factuality")
      expect(variants.first.instruction).to start_with("Be fair and reward")
    end

    it "caps the output at the requested count" do
      blocks = Array.new(5) { |i| "VARIANT:\nREASONING: r#{i}\nINSTRUCTION:\nv#{i}\nEND_VARIANT" }
      stub_llm(blocks.join("\n\n"))
      variants = described_class.new(metric, count: 3).call
      expect(variants.length).to eq(3)
    end

    it "drops blocks with an empty instruction" do
      stub_llm(<<~OUT)
        VARIANT:
        REASONING: missing instruction
        INSTRUCTION:
        END_VARIANT

        VARIANT:
        REASONING: ok
        INSTRUCTION:
        keep it
        END_VARIANT
      OUT
      variants = described_class.new(metric).call
      expect(variants.length).to eq(1)
    end
  end

  describe "#persist!" do
    it "saves each variant as a draft judge_version with source=suggestion and emits a Stripe-metering notification" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("completion_kit.judge_suggestion.generated") do |_, _, _, _, payload|
        events << payload
      end

      stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite me\nEND_VARIANT")
      gen = described_class.new(metric, count: 3, model: "claude-3-7-sonnet-latest")
      variants = gen.call
      versions = gen.persist!(variants)

      expect(versions.length).to eq(1)
      expect(versions.first).to be_a(CompletionKit::JudgeVersion)
      expect(versions.first.state).to eq("draft")
      expect(versions.first.source).to eq("suggestion")
      expect(events.length).to eq(1)
      expect(events.first[:metric_id]).to eq(metric.id)
      expect(events.first[:model]).to eq("claude-3-7-sonnet-latest")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it "rolls a previous suggestion draft off current when a new one is persisted" do
      stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nfirst\nEND_VARIANT")
      gen = described_class.new(metric, count: 1)
      previous = gen.persist!(gen.call).first
      previous.update!(current: true)

      gen2 = described_class.new(metric, count: 1)
      gen2.persist!(gen2.call)

      expect(previous.reload.current).to eq(false)
    end
  end

  describe "meta-prompt build with disagreements present" do
    it "includes recent disagreement context in the model input" do
      run = create(:completion_kit_run)
      response = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 5, ai_feedback: "perfect")
      jv = CompletionKit::JudgeVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: response, metric: metric, judge_version: jv,
             verdict: "disagree", corrected_score: 3, note: "missed nuance", created_by: "alice")

      captured = nil
      client = instance_double("CompletionKit::OpenAiClient")
      allow(client).to receive(:generate_completion) do |prompt, **|
        captured = prompt
        "VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite\nEND_VARIANT"
      end
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      described_class.new(metric, count: 1).call
      expect(captured).to include("Case 1")
      expect(captured).to include("Judge said 5")
      expect(captured).to include("Human said 3")
      expect(captured).to include("missed nuance")
    end
  end

  describe CompletionKit::JudgeCalibrationExamples do
    it "returns the latest disagreement examples with judge + human context" do
      run = create(:completion_kit_run)
      response = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 5, ai_feedback: "perfect")
      jv = CompletionKit::JudgeVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: response, metric: metric, judge_version: jv,
             verdict: "disagree", corrected_score: 3, note: "missed nuance", created_by: "alice")

      examples = described_class.for(metric)
      expect(examples.length).to eq(1)
      expect(examples.first[:judge_score]).to eq(5)
      expect(examples.first[:human_score]).to eq(3)
      expect(examples.first[:human_note]).to eq("missed nuance")
    end

    it "tolerates a disagreement whose review is missing (no judge score / feedback)" do
      run = create(:completion_kit_run)
      response = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      jv = CompletionKit::JudgeVersion.ensure_current_for(metric)
      create(:completion_kit_calibration,
             run: run, response: response, metric: metric, judge_version: jv,
             verdict: "disagree", corrected_score: 3, note: "no review", created_by: "ghost")

      examples = described_class.for(metric)
      expect(examples.first[:judge_score]).to be_nil
      expect(examples.first[:judge_feedback]).to be_nil
    end
  end
end
