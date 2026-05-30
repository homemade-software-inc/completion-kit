# This migration comes from completion_kit (originally 20260530000001)
class AddExcludedFromExamplesToCompletionKitCalibrations < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_calibrations, :excluded_from_examples, :boolean, null: false, default: false
  end
end
