module CompletionKit
  module TestRunLlmExtensions
    # Run tests using LLM API
    # This method processes the CSV data and generates completions for each row
    def run_tests
      return false unless process_csv_data
      
      # Get the LLM client for this prompt's model
      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
      
      unless client.configured?
        errors.add(:base, "LLM API not properly configured: #{client.configuration_errors.join(', ')}")
        return false
      end
      
      # Process each row of data
      processed_data.each do |row|
        # Apply variables to the prompt template
        processed_prompt = apply_variables_to_prompt(row)
        
        # Generate completion using the LLM API
        output = client.generate_completion(processed_prompt)
        
        # Create a test result
        test_results.create!(
          input_data: row.to_json,
          output_text: output,
          expected_output: extract_expected_output(row)
        )
      end
      
      true
    end
  end
end

# Extend the TestRun model with LLM integration methods
CompletionKit::TestRun.include CompletionKit::TestRunLlmExtensions
