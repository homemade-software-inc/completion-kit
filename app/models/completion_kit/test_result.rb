module CompletionKit
  class TestResult < ApplicationRecord
    belongs_to :test_run
    
    validates :input_data, presence: true
    validates :output_text, presence: true
    
    # Quality score from LLM judge evaluation (0-100)
    validates :quality_score, numericality: { 
      greater_than_or_equal_to: 0, 
      less_than_or_equal_to: 100,
      allow_nil: true 
    }
    
    # Store judge feedback as text
    validates :judge_feedback, presence: true, allow_nil: true
    
    # Expected output for comparison
    validates :expected_output, presence: true, allow_nil: true
    
    def evaluate_quality
      # This will be implemented in step 006
    end
  end
end
