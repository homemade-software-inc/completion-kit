# This migration comes from completion_kit (originally 20260328000001)
class AddErrorMessageToRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :error_message, :text
  end
end
