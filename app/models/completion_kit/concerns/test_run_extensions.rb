module CompletionKit
  module TestRunExtensions
    # Process CSV data and create test inputs
    # This method parses the CSV data and prepares it for LLM processing
    def process_csv_data
      # Use the CsvProcessor service to parse the CSV data
      rows = CsvProcessor.process(self)
      
      if rows.empty?
        return false
      end
      
      # Store the processed data for later use in run_tests
      @processed_data = rows
      true
    end
    
    # Get the processed data rows
    # @return [Array<Hash>] Array of hashes with variable mappings
    def processed_data
      @processed_data ||= []
    end
    
    # Apply variables to the prompt template for a specific row
    # @param row [Hash] Variable name-value pairs
    # @return [String] Processed prompt with variables replaced
    def apply_variables_to_prompt(row)
      CsvProcessor.apply_variables(prompt, row)
    end
    
    # Extract expected output from a data row if present
    # @param row [Hash] Variable name-value pairs
    # @return [String, nil] Expected output or nil if not present
    def extract_expected_output(row)
      row['expected_output']
    end
  end
end

# Extend the TestRun model with CSV processing methods
CompletionKit::TestRun.include CompletionKit::TestRunExtensions
