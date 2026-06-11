require "rails_helper"

RSpec.describe CompletionKit::PromptImprovementValidator do
  let(:prompt) { create(:completion_kit_prompt, template: "Summarize {{content}}", llm_model: "claude-x") }
  let(:run) { create(:completion_kit_run, prompt: prompt, judge_model: "claude-judge") }

  def scored_response(ai:, input: { content: "x" }.to_json, text: "out")
    response = create(:completion_kit_response, run: run, input_data: input, response_text: text)
    create(:completion_kit_review, response: response, ai_score: ai)
    response
  end

  describe "#call with injected generator + judge" do
    it "computes before/after averages and improved/regressed/unchanged with per-row deltas" do
      up = scored_response(ai: 3.0)
      down = scored_response(ai: 4.0)
      same = scored_response(ai: 3.0)
      after = { up.id => 5.0, down.id => 2.0, same.id => 3.0 }

      summary = described_class.new(run, "Summarize {{content}} well",
        generator: ->(_r) { "new" },
        judge: ->(r, _t) { after[r.id] }).call

      expect(summary["tested"]).to eq(3)
      expect(summary["improved"]).to eq(1)
      expect(summary["regressed"]).to eq(1)
      expect(summary["unchanged"]).to eq(1)
      expect(summary["improved"] + summary["unchanged"] + summary["regressed"]).to eq(summary["tested"])
      expect(summary["before_avg"]).to eq(3.33)
      expect(summary["after_avg"]).to eq(3.33)
      expect(summary["capped"]).to eq(false)
      expect(summary["rows"].find { |r| r["response_id"] == up.id }["delta"]).to eq(2.0)
    end

    it "skips a row whose candidate generation comes back blank" do
      scored_response(ai: 3.0)
      summary = described_class.new(run, "c", generator: ->(_r) { "" }, judge: ->(_r, _t) { 5.0 }).call
      expect(summary["tested"]).to eq(0)
    end

    it "skips a row whose judge returns nil" do
      scored_response(ai: 3.0)
      summary = described_class.new(run, "c", generator: ->(_r) { "new" }, judge: ->(_r, _t) { nil }).call
      expect(summary["tested"]).to eq(0)
    end

    it "skips a row whose generation or judging raises" do
      scored_response(ai: 3.0)
      summary = described_class.new(run, "c", generator: ->(_r) { raise "boom" }, judge: ->(_r, _t) { 5.0 }).call
      expect(summary["tested"]).to eq(0)
    end

    it "caps the held-out sample at 30 and reports the honest total" do
      35.times { scored_response(ai: 3.0) }
      summary = described_class.new(run, "c", generator: ->(_r) { "new" }, judge: ->(_r, _t) { 4.0 }).call
      expect(summary["tested"]).to eq(30)
      expect(summary["total"]).to eq(35)
      expect(summary["capped"]).to eq(true)
    end

    it "excludes responses that have no scored review from the held-out sample" do
      create(:completion_kit_response, run: run, input_data: { content: "x" }.to_json, response_text: "out")
      summary = described_class.new(run, "c", generator: ->(_r) { "new" }, judge: ->(_r, _t) { 4.0 }).call
      expect(summary["total"]).to eq(0)
      expect(summary["tested"]).to eq(0)
      expect(summary["before_avg"]).to be_nil
      expect(summary["after_avg"]).to be_nil
    end
  end

  describe "#call exercising the real generate + judge path" do
    before do
      create(:completion_kit_run_metric, run: run, metric: create(:completion_kit_metric, instruction: "Be fair"))
      allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})
    end

    it "re-renders the candidate, re-generates, and re-judges per metric" do
      scored_response(ai: 3.0, input: { content: "release" }.to_json)
      client = instance_double(CompletionKit::OpenAiClient, configured?: true)
      allow(client).to receive(:generate_completion).and_return("Brand new output")
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
      judge = instance_double(CompletionKit::JudgeService, evaluate: { score: 5.0, feedback: "great" })
      allow(CompletionKit::JudgeService).to receive(:new).and_return(judge)

      summary = described_class.new(run, "Summarize {{content}} concisely").call

      expect(summary["tested"]).to eq(1)
      expect(summary["after_avg"]).to eq(5.0)
      expect(summary["improved"]).to eq(1)
    end

    it "skips rows when the generation model is not configured" do
      scored_response(ai: 3.0)
      client = instance_double(CompletionKit::OpenAiClient, configured?: false, configuration_errors: ["no key"])
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(described_class.new(run, "c").call["tested"]).to eq(0)
    end

    it "skips rows when generation returns an Error string" do
      scored_response(ai: 3.0)
      client = instance_double(CompletionKit::OpenAiClient, configured?: true)
      allow(client).to receive(:generate_completion).and_return("Error: rate limited")
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(described_class.new(run, "c").call["tested"]).to eq(0)
    end

    it "tolerates malformed input_data and a run with no metrics" do
      run.run_metrics.destroy_all
      response = scored_response(ai: 3.0)
      response.update_column(:input_data, "{not json")
      client = instance_double(CompletionKit::OpenAiClient, configured?: true)
      allow(client).to receive(:generate_completion).and_return("Brand new output")
      allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)

      expect(described_class.new(run, "c").call["tested"]).to eq(0)
    end
  end
end
