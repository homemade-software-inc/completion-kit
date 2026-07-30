# This migration comes from completion_kit (originally 20260730000001)
class AddJudgeTemperatureToCompletionKitRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_runs, :judge_temperature, :float, default: 0.0
  end
end
