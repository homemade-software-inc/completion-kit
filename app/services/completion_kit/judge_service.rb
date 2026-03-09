module CompletionKit
  class JudgeService
    def initialize(config = {})
      @config = config
      @judge_model = config[:judge_model] || CompletionKit.config.judge_model
      @judge_client = LlmClient.for_model(@judge_model, ApiConfig.for_model(@judge_model))
    end

    def evaluate(output, expected_output = nil, prompt = nil, criteria = {})
      return { score: 0, feedback: "Judge not configured" } unless @judge_client.configured?
      
      judge_prompt = build_judge_prompt(output, expected_output, prompt, criteria)
      
      begin
        response = @judge_client.generate_completion(judge_prompt, model: @judge_model)
        parse_judge_response(response)
      rescue => e
        { score: 0, feedback: "Error during evaluation: #{e.message}" }
      end
    end
    
    private

    def build_judge_prompt(output, expected_output, prompt, criteria)
      judge_prompt = <<~PROMPT
        You are an expert evaluator of AI-generated content.
        Score the AI-generated output on a rubric from 1 to 10.
        First choose the best fitting score range, then choose the exact score within that range.
        Use each range's criteria and reasoning cue to justify the score.

        Original prompt template:
        #{prompt || "Not provided"}

        Input data for this result:
        #{criteria[:input_data] || "Not provided"}

        AI-generated output:
        #{output}
      PROMPT

      if expected_output.present?
        judge_prompt += <<~PROMPT
          Expected output:
          #{expected_output}
        PROMPT
      end

      if criteria[:review_guidance].present?
        judge_prompt += <<~PROMPT
          Assessment guidance:
          #{criteria[:review_guidance]}
        PROMPT
      end

      judge_prompt += <<~PROMPT
        Structured rubric:
        #{criteria[:rubric_text].presence || CompletionKit::Metric.default_rubric_text}
      PROMPT

      if criteria[:human_examples].present?
        judge_prompt += <<~PROMPT
          Human-reviewed calibration examples:
        PROMPT

        criteria[:human_examples].each_with_index do |example, index|
          judge_prompt += <<~PROMPT
            Example #{index + 1}
            Input: #{example[:input_data]}
            Output: #{example[:output_text]}
            Human score: #{example[:human_score]}
            Human notes: #{example[:human_feedback].presence || "None"}
          PROMPT
        end
      end

      judge_prompt += <<~PROMPT
        Return exactly this format:
        Score: [1-10]
        Feedback: [concise explanation that references the rubric]
      PROMPT

      judge_prompt
    end

    def parse_judge_response(response)
      score_match = response.match(/Score:\s*(\d+(?:\.\d+)?)/)
      feedback_match = response.match(/Feedback:\s*(.+)/m)
      
      score = score_match ? score_match[1].to_f : 0
      feedback = feedback_match ? feedback_match[1].strip : "No feedback provided"
      
      score = [[score, 0].max, 10].min
      
      { score: score, feedback: feedback }
    end
  end
end
