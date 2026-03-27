# This migration comes from completion_kit (originally 20260327000001)
class AddProgressToRuns < ActiveRecord::Migration[7.0]
  def change
    add_column :completion_kit_runs, :progress_current, :integer, default: 0
    add_column :completion_kit_runs, :progress_total, :integer, default: 0
  end
end
