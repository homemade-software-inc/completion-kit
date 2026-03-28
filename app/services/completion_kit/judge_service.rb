require "faraday"

module CompletionKit
  class JudgeService
    def initialize(config = {})
      @config = config
      @judge_model = config[:judge_model] || CompletionKit.config.judge_model
      @judge_client = LlmClient.for_model(@judge_model, ApiConfig.for_model(@judge_model))
    end

    def evaluate(output, expected_output = nil, prompt = nil, criteria: nil, evaluation_steps: nil, rubric_text: nil, human_examples: nil, **_extras)
      return { score: 1, feedback: "Judge not configured" } unless @judge_client.configured?

      judge_prompt = build_judge_prompt(output, expected_output, prompt,
        criteria: criteria, evaluation_steps: evaluation_steps,
        rubric_text: rubric_text, human_examples: human_examples)

      response = @judge_client.generate_completion(judge_prompt, model: @judge_model)
      raise StandardError, response if response.start_with?("Error:")
      parse_judge_response(response)
    rescue Faraday::Error
      raise
    rescue => e
      { score: 1, feedback: "Error during evaluation: #{e.message}" }
    end

    private

    def build_judge_prompt(output, expected_output, prompt, criteria: nil, evaluation_steps: nil, rubric_text: nil, human_examples: nil)
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

      if evaluation_steps.present? && evaluation_steps.any?
        judge_prompt += "\nEvaluation steps:\n#{evaluation_steps.each_with_index.map { |step, i| "#{i + 1}. #{step}" }.join("\n")}\n"
      end

      if human_examples.present?
        judge_prompt += "\nCalibration examples:\n"
        human_examples.each_with_index do |example, index|
          judge_prompt += "Example #{index + 1}: score=#{example[:human_score]} output=#{example[:response_text].to_s.truncate(200)}\n"
        end
      end

      judge_prompt += <<~PROMPT

        Original prompt: #{prompt || "Not provided"}
        #{expected_output.present? ? "Expected output: #{expected_output}" : ""}
        AI output to evaluate: #{output}
      PROMPT

      judge_prompt
    end

    def parse_judge_response(response)
      score_match = response.match(/\*{0,2}Score:?\*{0,2}\s*(\d+(?:\.\d+)?)/i)
      feedback_match = response.match(/\*{0,2}Feedback:?\*{0,2}\s*(.+)/mi)

      score = score_match ? score_match[1].to_f : 1
      feedback = if feedback_match
                   feedback_match[1].strip
                 elsif score_match
                   "No feedback provided"
                 else
                   "Could not parse judge response: #{response.truncate(500)}"
                 end

      score = [[score, 1].max, 5].min

      { score: score, feedback: feedback }
    end
  end
end
