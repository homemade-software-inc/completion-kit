require "faraday"

module CompletionKit
  class JudgeParseError < StandardError; end

  class JudgeService
    def initialize(config = {})
      @config = config
      @judge_model = config[:judge_model] || CompletionKit.config.judge_model
      @judge_client = LlmClient.for_model(@judge_model, ApiConfig.for_model(@judge_model))
    end

    def evaluate(output, expected_output = nil, prompt = nil, criteria: nil, rubric_text: nil, input_data: nil, **_extras)
      raise CompletionKit::ConfigurationError, "Judge not configured" unless @judge_client.configured?

      judge_prompt = build_judge_prompt(output, expected_output, prompt,
        criteria: criteria,
        rubric_text: rubric_text,
        input_data: input_data)

      response = @judge_client.generate_completion(judge_prompt, model: @judge_model)
      raise StandardError, response if response.start_with?("Error:")
      parse_judge_response(response)
    end

    private

    def build_judge_prompt(output, expected_output, prompt, criteria: nil, rubric_text: nil, input_data: nil)
      judge_prompt = <<~PROMPT
        You are an expert evaluator. You MUST respond with ONLY two lines in this exact format, nothing else:

        Score: <integer from 1 to 5>
        Feedback: <one sentence explaining why>

        Do not include any other text, markdown, or explanation. Just those two lines.

        Use this rubric to choose the score:
        #{rubric_text.presence || CompletionKit::Metric.default_rubric_text}
      PROMPT

      if criteria.present?
        judge_prompt += "\nCriteria: #{criteria}\n"
      end

      judge_prompt += <<~PROMPT

        Original prompt: #{prompt || "Not provided"}
        #{input_data.present? ? "Input data: #{input_data}" : ""}
        #{expected_output.present? ? "Expected output: #{expected_output}" : ""}
        AI output to evaluate: #{output}
      PROMPT

      judge_prompt
    end

    def parse_judge_response(response)
      score_match = response.match(/\*{0,2}Score:?\*{0,2}\s*(\d+(?:\.\d+)?)/i)
      feedback_match = response.match(/\*{0,2}Feedback:?\*{0,2}\s*(.+)/mi)

      unless score_match
        raise CompletionKit::JudgeParseError,
              "Could not parse judge response: #{response.truncate(500)}"
      end

      score = [[score_match[1].to_f, 1].max, 5].min
      feedback = feedback_match ? feedback_match[1].strip : "No feedback provided"

      { score: score, feedback: feedback }
    end
  end
end
