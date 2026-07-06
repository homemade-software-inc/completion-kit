class AddExpectedColumnToCompletionKitRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_runs, :expected_column, :string
  end
end
