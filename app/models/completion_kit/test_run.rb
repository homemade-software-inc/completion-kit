module CompletionKit
  class TestRun < ApplicationRecord
    belongs_to :prompt
    has_many :test_results, dependent: :destroy
    
    validates :name, presence: true
    
    def process_csv_data
      # This will be implemented in step 004
    end
    
    def run_tests
      # This will be implemented in step 005
    end
  end
end
