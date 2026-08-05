# This migration comes from completion_kit (originally 20260804000001)
class AddJudgeTemperatureIgnoredToRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :completion_kit_runs, :judge_temperature_ignored, :boolean, default: false, null: false
  end
end
