class AllowJudgeOnlyRuns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :completion_kit_runs, :prompt_id, true
    add_column :completion_kit_runs, :output_column, :string
  end
end
