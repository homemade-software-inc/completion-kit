# This migration comes from completion_kit (originally 20260507150000)
class AddTemperatureIgnoredToRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :temperature_ignored, :boolean, default: false, null: false
  end
end
