# This migration comes from completion_kit (originally 20250401192953)
class CreateCompletionKitTestResults < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_test_results do |t|
      t.references :test_run, null: false, foreign_key: { to_table: :completion_kit_test_runs }
      t.string :status
      t.text :input_data
      t.text :output_text
      t.text :expected_output
      t.text :judge_feedback
      t.decimal :quality_score, precision: 5, scale: 2
      
      t.timestamps
    end
  end
end