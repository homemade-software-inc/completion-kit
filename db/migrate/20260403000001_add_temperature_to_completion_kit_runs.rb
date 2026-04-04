class AddTemperatureToCompletionKitRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :temperature, :float, default: 1.0
  end
end
