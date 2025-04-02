module CompletionKit
  class CsvProcessor
    require 'csv'
    
    # Process CSV data from a test run and extract variables
    # @param test_run [TestRun] The test run containing CSV data
    # @return [Array<Hash>] Array of hashes with variable mappings
    def self.process(test_run)
      return [] if test_run.csv_data.blank?
      
      begin
        # Parse CSV data with headers
        csv_data = CSV.parse(test_run.csv_data, headers: true)
        
        # Convert to array of hashes
        rows = csv_data.map(&:to_h)
        
        # Validate that we have data
        if rows.empty?
          test_run.errors.add(:csv_data, "No data rows found in CSV")
          return []
        end
        
        # Validate that we have all required variables from the prompt template
        validate_variables(test_run, rows.first.keys)
        
        rows
      rescue CSV::MalformedCSVError => e
        test_run.errors.add(:csv_data, "Invalid CSV format: #{e.message}")
        []
      end
    end
    
    # Extract variable names from prompt template
    # @param prompt [Prompt] The prompt template
    # @return [Array<String>] Array of variable names
    def self.extract_variables(prompt)
      return [] if prompt.template.blank?
      
      # Extract all {{variable}} patterns from the template
      prompt.template.scan(/\{\{([^}]+)\}\}/).flatten.uniq
    end
    
    # Validate that CSV headers include all variables from the prompt template
    # @param test_run [TestRun] The test run
    # @param headers [Array<String>] CSV headers
    # @return [Boolean] True if valid, false otherwise
    def self.validate_variables(test_run, headers)
      prompt_variables = extract_variables(test_run.prompt)
      missing_variables = prompt_variables - headers
      
      if missing_variables.any?
        test_run.errors.add(:csv_data, "Missing required variables in CSV: #{missing_variables.join(', ')}")
        return false
      end
      
      true
    end
    
    # Apply variable values to a prompt template
    # @param prompt [Prompt] The prompt template
    # @param variables [Hash] Variable name-value pairs
    # @return [String] Processed prompt with variables replaced
    def self.apply_variables(prompt, variables)
      result = prompt.template.dup
      
      variables.each do |name, value|
        result.gsub!(/\{\{#{name}\}\}/, value.to_s)
      end
      
      result
    end
  end
end
