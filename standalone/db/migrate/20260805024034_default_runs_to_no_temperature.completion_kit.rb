# This migration comes from completion_kit (originally 20260804000002)
class DefaultRunsToNoTemperature < ActiveRecord::Migration[8.0]
  def up
    change_column_default :completion_kit_runs, :temperature, nil
  end

  def down
    change_column_default :completion_kit_runs, :temperature, 1.0
  end
end
