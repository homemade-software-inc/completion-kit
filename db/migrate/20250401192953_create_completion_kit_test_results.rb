class CreateCompletionKitTestResults < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_test_results do |t|
      t.references :test_run, null: false, foreign_key: { to_table: :completion_kit_test_runs }
      t.string :status
      t.text :input
      t.text :output
      t.text :feedback
      t.decimal :score, precision: 5, scale: 2
      
      t.timestamps
    end
  end
end