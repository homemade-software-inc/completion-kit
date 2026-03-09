class AddHumanReviewFieldsToCompletionKitTestResults < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_test_results, :human_score, :decimal, precision: 4, scale: 1
    add_column :completion_kit_test_results, :human_feedback, :text
    add_column :completion_kit_test_results, :human_reviewer_name, :string
    add_column :completion_kit_test_results, :human_reviewed_at, :datetime
  end
end
