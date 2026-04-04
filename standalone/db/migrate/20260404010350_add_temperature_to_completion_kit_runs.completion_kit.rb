# This migration comes from completion_kit (originally 20260403000001)
class AddTemperatureToCompletionKitRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :temperature, :float, default: 0.7
  end
end
