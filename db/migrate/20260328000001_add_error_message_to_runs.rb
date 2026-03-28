class AddErrorMessageToRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :error_message, :text
  end
end
