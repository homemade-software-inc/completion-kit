module CompletionKit
  class JudgeService
    # Service for evaluating the quality of LLM outputs using an LLM judge
    
    # Initialize the judge service
    # @param config [Hash] Configuration options
    def initialize(config = {})
      @config = config
      @judge_model = config[:judge_model] || 'gpt-4'
      @judge_client = LlmClient.for_model(@judge_model, ApiConfig.for_model(@judge_model))
    end
    
    # Evaluate the quality of an output against an expected output
    # @param output [String] The generated output to evaluate
    # @param expected_output [String] The expected output (optional)
    # @param prompt [String] The original prompt
    # @param criteria [Hash] Evaluation criteria
    # @return [Hash] Evaluation results with score and feedback
    def evaluate(output, expected_output = nil, prompt = nil, criteria = {})
      return { score: 0, feedback: "Judge not configured" } unless @judge_client.configured?
      
      judge_prompt = build_judge_prompt(output, expected_output, prompt, criteria)
      
      begin
        response = @judge_client.generate_completion(judge_prompt)
        parse_judge_response(response)
      rescue => e
        { score: 0, feedback: "Error during evaluation: #{e.message}" }
      end
    end
    
    private
    
    # Build the prompt for the judge
    # @param output [String] The generated output to evaluate
    # @param expected_output [String] The expected output (optional)
    # @param prompt [String] The original prompt
    # @param criteria [Hash] Evaluation criteria
    # @return [String] The judge prompt
    def build_judge_prompt(output, expected_output, prompt, criteria)
      judge_prompt = <<~PROMPT
        You are an expert evaluator of AI-generated content. Your task is to evaluate the quality of an AI-generated output.
        
        Original prompt:
        #{prompt || "Not provided"}
        
        AI-generated output:
        #{output}
        
      PROMPT
      
      if expected_output.present?
        judge_prompt += <<~PROMPT
          Expected output:
          #{expected_output}
          
          Compare the AI-generated output with the expected output. Consider:
          1. Accuracy - Does the output match the expected information?
          2. Completeness - Does the output cover all points in the expected output?
          3. Clarity - Is the output clear and well-structured?
          
        PROMPT
      else
        judge_prompt += <<~PROMPT
          Evaluate the output based on:
          1. Relevance - Does the output address the prompt effectively?
          2. Coherence - Is the output logically structured and easy to follow?
          3. Informativeness - Does the output provide valuable information?
          4. Clarity - Is the output clear and well-written?
          
        PROMPT
      end
      
      judge_prompt += <<~PROMPT
        Provide your evaluation in the following format:
        
        Score: [0-100]
        Feedback: [Your detailed feedback explaining the score]
      PROMPT
      
      judge_prompt
    end
    
    # Parse the judge's response to extract score and feedback
    # @param response [String] The judge's response
    # @return [Hash] Parsed score and feedback
    def parse_judge_response(response)
      score_match = response.match(/Score:\s*(\d+)/)
      feedback_match = response.match(/Feedback:\s*(.+)/m)
      
      score = score_match ? score_match[1].to_i : 0
      feedback = feedback_match ? feedback_match[1].strip : "No feedback provided"
      
      # Ensure score is within valid range
      score = [[score, 0].max, 100].min
      
      { score: score, feedback: feedback }
    end
  end
end
