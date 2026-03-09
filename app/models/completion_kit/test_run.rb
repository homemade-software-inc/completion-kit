module CompletionKit
  class TestRun < ApplicationRecord
    STATUSES = %w[draft running completed evaluated failed].freeze

    belongs_to :prompt
    has_many :test_results, dependent: :destroy
    
    validates :name, presence: true
    validates :csv_data, presence: true
    validates :status, inclusion: { in: STATUSES }

    before_validation :reset_parsed_csv_rows
    before_validation :set_default_status, on: :create

    def process_csv_data
      parsed_csv_rows.present?
    end
    
    def run_tests
      rows = parsed_csv_rows
      return false if rows.empty?

      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

      unless client.configured?
        errors.add(:base, "LLM API not properly configured: #{client.configuration_errors.join(', ')}")
        update_column(:status, "failed") if persisted?
        return false
      end

      transaction do
        update!(status: "running")
        test_results.delete_all

        rows.each do |row|
          output = client.generate_completion(apply_variables_to_prompt(row), model: prompt.llm_model)

          test_results.create!(
            status: output.to_s.start_with?("Error:") ? "failed" : "completed",
            input_data: row.to_json,
            output_text: output,
            expected_output: extract_expected_output(row)
          )
        end

        update!(status: "completed")
      end

      true
    rescue StandardError => e
      errors.add(:base, "Failed to run tests: #{e.message}")
      update_column(:status, "failed") if persisted?
      false
    end

    def evaluate_results
      successful_evaluations = test_results.count(&:evaluate_quality)
      update_column(:status, "evaluated") if successful_evaluations.positive?
      successful_evaluations
    end

    def apply_variables_to_prompt(row)
      CsvProcessor.apply_variables(prompt, row)
    end

    def extract_expected_output(row)
      row["expected_output"]
    end

    private

    def parsed_csv_rows
      @parsed_csv_rows ||= CsvProcessor.process(self)
    end

    def set_default_status
      self.status ||= "draft"
    end

    def reset_parsed_csv_rows
      @parsed_csv_rows = nil
    end
  end
end
