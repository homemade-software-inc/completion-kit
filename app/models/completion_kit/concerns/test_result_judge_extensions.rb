module CompletionKit
  module TestResultJudgeExtensions
    # Evaluate the quality of this test result using an LLM judge
    def evaluate_quality
      return false if output_text.blank?
      
      # Create a judge service
      judge = JudgeService.new
      
      # Get the original prompt and input data
      input_data_hash = JSON.parse(input_data) rescue {}
      original_prompt = test_run.prompt.template
      
      # Evaluate the output
      evaluation = judge.evaluate(
        output_text,
        expected_output,
        original_prompt,
        { test_run_id: test_run_id }
      )
      
      # Update the test result with the evaluation
      update(
        quality_score: evaluation[:score],
        judge_feedback: evaluation[:feedback]
      )
      
      true
    rescue => e
      update(
        quality_score: 0,
        judge_feedback: "Error during evaluation: #{e.message}"
      )
      false
    end
  end
end

# Extend the TestResult model with judge functionality
CompletionKit::TestResult.include CompletionKit::TestResultJudgeExtensions
