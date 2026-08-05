class AddJudgeTemperatureIgnoredToRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :completion_kit_runs, :judge_temperature_ignored, :boolean, default: false, null: false
  end
end
