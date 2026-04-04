require "rails_helper"

RSpec.describe CompletionKit::PromptImprovementService do
  let(:prompt) { create(:completion_kit_prompt, template: "Summarize {{text}}", llm_model: "gpt-4.1") }
  let(:run) { create(:completion_kit_run, prompt: prompt) }
  let(:client) { instance_double(CompletionKit::LlmClient) }

  before do
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(client)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({ api_key: "test" })
  end

  describe "#suggest" do
    it "returns parsed reasoning and suggested template from a well-formed LLM response" do
      resp1 = create(:completion_kit_response, run: run, response_text: "Good output", input_data: '{"text":"hello"}', expected_output: "Expected")
      metric = create(:completion_kit_metric, name: "Clarity")
      create(:completion_kit_review, response: resp1, metric: metric, metric_name: "Clarity", ai_score: 3.0, ai_feedback: "Needs work")

      allow(client).to receive(:generate_completion).and_return(<<~LLM)
        REASONING:
        - The prompt lacks specificity
        - Adding context improves results

        IMPROVED_PROMPT:
        Please summarize the following text concisely: {{text}}
      LLM

      result = described_class.new(run).suggest

      expect(result["reasoning"]).to include("prompt lacks specificity")
      expect(result["suggested_template"]).to include("{{text}}")
      expect(result["original_template"]).to eq("Summarize {{text}}")
    end

    it "handles LLM response missing REASONING/IMPROVED_PROMPT sections" do
      create(:completion_kit_response, run: run, response_text: "Output")

      allow(client).to receive(:generate_completion).and_return("Just a plain text response with no sections")

      result = described_class.new(run).suggest

      expect(result["reasoning"]).to eq("No reasoning provided.")
      expect(result["suggested_template"]).to eq("Just a plain text response with no sections")
    end

    it "includes metric averages and overall score in the meta-prompt" do
      resp1 = create(:completion_kit_response, run: run, response_text: "Output", input_data: nil, expected_output: nil)
      metric = create(:completion_kit_metric, name: "Quality")
      create(:completion_kit_review, response: resp1, metric: metric, metric_name: "Quality", ai_score: 4.5, ai_feedback: "Great")

      allow(client).to receive(:generate_completion) do |meta_prompt, **_opts|
        expect(meta_prompt).to include("Overall Score:")
        expect(meta_prompt).to include("Metric Averages")
        expect(meta_prompt).to include("Quality")
        "REASONING:\n- Good\n\nIMPROVED_PROMPT:\nBetter {{text}}"
      end

      described_class.new(run).suggest
    end
  end
end
