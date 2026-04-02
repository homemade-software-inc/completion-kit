module CompletionKit
  class PromptImprovementService
    def initialize(run)
      @run = run
      @prompt = run.prompt
    end

    def suggest
      client = LlmClient.for_model(@prompt.llm_model, ApiConfig.for_model(@prompt.llm_model))
      response = client.generate_completion(build_meta_prompt, model: @prompt.llm_model, max_tokens: 2000, temperature: 0.4)
      parse_response(response)
    end

    private

    def build_meta_prompt
      sections = []
      sections << "You are an expert prompt engineer. Analyze the following prompt and its test results, then suggest an improved version."
      sections << ""
      sections << "## Current Prompt"
      sections << "```"
      sections << @prompt.template
      sections << "```"
      sections << ""
      sections << "## Test Results"
      sections << ""

      reviews_by_response = @run.responses.includes(:reviews).limit(20)

      reviews_by_response.each_with_index do |resp, i|
        sections << "### Response #{i + 1}"
        if resp.input_data.present?
          sections << "Input: #{resp.input_data.truncate(200)}"
        end
        sections << "Output: #{resp.response_text.to_s.truncate(300)}"
        if resp.expected_output.present?
          sections << "Expected: #{resp.expected_output.truncate(200)}"
        end
        resp.reviews.each do |review|
          sections << "  #{review.metric_name}: #{review.ai_score}/5 — #{review.ai_feedback}"
        end
        sections << ""
      end

      avg = @run.avg_score
      sections << "## Overall Score: #{avg}/5" if avg

      metric_avgs = @run.metric_averages
      if metric_avgs.any?
        sections << "## Metric Averages"
        metric_avgs.each { |m| sections << "  #{m[:name]}: #{m[:avg]}/5" }
        sections << ""
      end

      sections << "## Instructions"
      sections << "Based on the test results above, suggest an improved version of the prompt."
      sections << "Focus on addressing the weakest scoring areas while preserving what works well."
      sections << ""
      sections << "Respond in EXACTLY this format:"
      sections << ""
      sections << "REASONING:"
      sections << "<2-4 bullet points explaining what you'd change and why>"
      sections << ""
      sections << "IMPROVED_PROMPT:"
      sections << "<the full improved prompt template, preserving all {{variable}} placeholders>"

      sections.join("\n")
    end

    def parse_response(text)
      reasoning_match = text.match(/REASONING:\s*\n(.*?)(?=IMPROVED_PROMPT:)/m)
      prompt_match = text.match(/IMPROVED_PROMPT:\s*\n(.*)/m)

      {
        reasoning: reasoning_match ? reasoning_match[1].strip : "No reasoning provided.",
        suggested_template: prompt_match ? prompt_match[1].strip : text.strip,
        original_template: @prompt.template
      }
    end
  end
end
