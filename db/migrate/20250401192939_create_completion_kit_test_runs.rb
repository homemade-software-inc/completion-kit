class CreateCompletionKitTestRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_test_runs do |t|
      t.string :name
      t.text :description
      t.references :prompt, null: false, foreign_key: { to_table: :completion_kit_prompts }
      t.text :input_data
      t.text :output_data
      t.string :status
      
      t.timestamps
    end
  end
end