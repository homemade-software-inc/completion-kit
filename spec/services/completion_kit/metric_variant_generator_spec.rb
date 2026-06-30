require "rails_helper"

RSpec.describe CompletionKit::MetricVariantGenerator, type: :service do
  let(:metric) { create(:completion_kit_metric, instruction: "Be fair") }

  around do |example|
    original = CompletionKit.config.judge_model
    CompletionKit.config.judge_model = "claude-judge-default"
    example.run
  ensure
    CompletionKit.config.judge_model = original
  end

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

  describe "check metrics" do
    it "returns [] without calling the LLM" do
      check_metric = create(:completion_kit_metric, :check)
      expect(CompletionKit::LlmClient).not_to receive(:for_model)
      expect(described_class.new(check_metric).call).to eq([])
    end
  end

  describe "#persist!" do
    it "saves each variant as a draft metric_version with source=suggestion and emits a Stripe-metering notification" do
      events = []
      subscriber = ActiveSupport::Notifications.subscribe("completion_kit.judge_suggestion.generated") do |_, _, _, _, payload|
        events << payload
      end

      stub_llm("VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite me\nEND_VARIANT")
      gen = described_class.new(metric, count: 3, model: "claude-3-7-sonnet-latest")
      variants = gen.call
      versions = gen.persist!(variants)

      expect(versions.length).to eq(1)
      expect(versions.first).to be_a(CompletionKit::MetricVersion)
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

  describe "rubric rewrites" do
    it "parses a RUBRIC block when the model returns one and persists it on the draft" do
      stub_llm(<<~OUT)
        VARIANT:
        REASONING: tighten bands
        INSTRUCTION:
        new instruction
        RUBRIC:
        5: top tier description
        4: very good description
        3: middling description
        2: poor description
        1: awful description
        END_VARIANT
      OUT
      gen = described_class.new(metric, count: 1)
      variants = gen.call
      expect(variants.length).to eq(1)
      expect(variants.first.rubric_bands).to be_an(Array)
      expect(variants.first.rubric_bands.length).to eq(5)
      expect(variants.first.rubric_bands.first).to eq({"stars" => 5, "description" => "top tier description"})

      version = gen.persist!(variants).first
      expect(version.rubric_bands.first["description"]).to eq("top tier description")
    end

    it "falls back to the metric's current rubric when the RUBRIC block is missing" do
      stub_llm("VARIANT:\nREASONING: no rubric\nINSTRUCTION:\nfresh instruction\nEND_VARIANT")
      gen = described_class.new(metric, count: 1)
      variants = gen.call
      expect(variants.first.rubric_bands).to be_nil
      version = gen.persist!(variants).first
      expect(version.rubric_bands).to eq(metric.rubric_bands)
    end

    it "ignores a malformed RUBRIC block (not 5 bands) and keeps the metric's rubric" do
      stub_llm(<<~OUT)
        VARIANT:
        REASONING: half-rubric
        INSTRUCTION:
        new instruction
        RUBRIC:
        5: only one band
        END_VARIANT
      OUT
      gen = described_class.new(metric, count: 1)
      variants = gen.call
      expect(variants.first.rubric_bands).to be_nil
    end
  end

  describe "count clamping" do
    it "clamps a request for 99 down to MAX_VARIANT_COUNT" do
      gen = described_class.new(metric, count: 99)
      expect(gen.instance_variable_get(:@count)).to eq(described_class::MAX_VARIANT_COUNT)
    end

    it "uses the default when count is 0 or negative" do
      [0, -1].each do |bad|
        gen = described_class.new(metric, count: bad)
        expect(gen.instance_variable_get(:@count)).to eq(described_class::DEFAULT_VARIANT_COUNT)
      end
    end
  end

  describe "meta-prompt build with disagreements present" do
    it "includes recent disagreement context in the model input" do
      run = create(:completion_kit_run)
      response = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 5, ai_feedback: "perfect")
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric, metric_version: jv,
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

    it "also includes borderline (rubric-ambiguous) cases when present, with and without notes" do
      run = create(:completion_kit_run)
      r1 = create(:completion_kit_response, run: run, input_data: "Q1?", response_text: "A1.")
      r2 = create(:completion_kit_response, run: run, input_data: "Q2?", response_text: "A2.")
      create(:completion_kit_review, response: r1, metric: metric, metric_name: metric.name, ai_score: 4, ai_feedback: "hmm")
      create(:completion_kit_review, response: r2, metric: metric, metric_name: metric.name, ai_score: 4, ai_feedback: "hmm")
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: r1, metric: metric, metric_version: jv,
             verdict: "borderline", note: "two bands overlap here", created_by: "alice")
      create(:completion_kit_agreement,
             run: run, response: r2, metric: metric, metric_version: jv,
             verdict: "borderline", note: nil, created_by: "bob")

      captured = nil
      client = instance_double("CompletionKit::OpenAiClient")
      allow(client).to receive(:generate_completion) do |prompt, **|
        captured = prompt
        "VARIANT:\nREASONING: r\nINSTRUCTION:\nrewrite\nEND_VARIANT"
      end
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      described_class.new(metric, count: 1).call
      expect(captured).to include("Rubric-ambiguous cases")
      expect(captured).to include("Borderline 1")
      expect(captured).to include("Borderline 2")
      expect(captured).to include("two bands overlap here")
    end
  end

  describe CompletionKit::MetricAgreementExamples do
    it "returns the latest disagreement examples with judge + human context" do
      run = create(:completion_kit_run)
      response = create(:completion_kit_response, run: run, input_data: "Q?", response_text: "A.")
      create(:completion_kit_review, response: response, metric: metric, metric_name: metric.name, ai_score: 5, ai_feedback: "perfect")
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric, metric_version: jv,
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
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric, metric_version: jv,
             verdict: "disagree", corrected_score: 3, note: "no review", created_by: "ghost")

      examples = described_class.for(metric)
      expect(examples.first[:judge_score]).to be_nil
      expect(examples.first[:judge_feedback]).to be_nil
    end
  end

  describe "default judge-model resolution" do
    it "resolves a judging model from the registry when neither a model nor config is set" do
      CompletionKit.config.judge_model = nil
      create(:completion_kit_model, provider: "anthropic", model_id: "claude-resolved", supports_judging: true)
      client = instance_double("CompletionKit::OpenAiClient", generate_completion: "VARIANT:\nREASONING: r\nINSTRUCTION:\nx\nEND_VARIANT")
      expect(CompletionKit::LlmClient).to receive(:for_model).with("claude-resolved", anything).and_return(client)

      described_class.new(metric).call
    end

    it "raises ConfigurationError when no judging model can be resolved" do
      CompletionKit.config.judge_model = nil

      expect { described_class.new(metric).call }.to raise_error(CompletionKit::ConfigurationError, /No judging model/)
    end
  end
end
