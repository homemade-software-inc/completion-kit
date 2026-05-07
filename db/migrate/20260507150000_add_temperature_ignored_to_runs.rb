class AddTemperatureIgnoredToRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :temperature_ignored, :boolean, default: false, null: false
  end
end
