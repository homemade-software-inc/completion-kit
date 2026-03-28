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
      parse_judge_response(response)
    rescue Faraday::Error
      raise
    rescue => e
      { score: 1, feedback: "Error during evaluation: #{e.message}" }
    end

    private

    def build_judge_prompt(output, expected_output, prompt, criteria: nil, evaluation_steps: nil, rubric_text: nil, human_examples: nil)
      judge_prompt = <<~PROMPT
        You are an expert evaluator of AI-generated content.
        Score the AI-generated output on a rubric from 1 to 5 stars.
        First read the criteria and evaluation steps, then use the rubric to choose the best fitting score.

        Original prompt template:
        #{prompt || "Not provided"}

        AI-generated output:
        #{output}
      PROMPT

      if expected_output.present?
        judge_prompt += <<~PROMPT
          Expected output:
          #{expected_output}
        PROMPT
      end

      if criteria.present?
        judge_prompt += <<~PROMPT
          Criteria:
          #{criteria}
        PROMPT
      end

      if evaluation_steps.present? && evaluation_steps.any?
        judge_prompt += <<~PROMPT
          Evaluation steps:
          #{evaluation_steps.each_with_index.map { |step, i| "#{i + 1}. #{step}" }.join("\n")}
        PROMPT
      end

      judge_prompt += <<~PROMPT
        Rubric:
        #{rubric_text.presence || CompletionKit::Metric.default_rubric_text}
      PROMPT

      if human_examples.present?
        judge_prompt += "Human-reviewed calibration examples:\n"

        human_examples.each_with_index do |example, index|
          judge_prompt += <<~PROMPT
            Example #{index + 1}
            Input: #{example[:input_data]}
            Output: #{example[:response_text]}
            Human score: #{example[:human_score]}
            Human notes: #{example[:human_feedback].presence || "None"}
          PROMPT
        end
      end

      judge_prompt += <<~PROMPT
        Return exactly this format:
        Score: [1-5]
        Feedback: [concise explanation that references the rubric]
      PROMPT

      judge_prompt
    end

    def parse_judge_response(response)
      score_match = response.match(/Score:\s*(\d+(?:\.\d+)?)/)
      feedback_match = response.match(/Feedback:\s*(.+)/m)

      score = score_match ? score_match[1].to_f : 1
      feedback = feedback_match ? feedback_match[1].strip : "No feedback provided"

      score = [[score, 1].max, 5].min

      { score: score, feedback: feedback }
    end
  end
end
