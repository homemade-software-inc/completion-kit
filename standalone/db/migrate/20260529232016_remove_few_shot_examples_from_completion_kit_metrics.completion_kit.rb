# This migration comes from completion_kit (originally 20260529000001)
class RemoveFewShotExamplesFromCompletionKitMetrics < ActiveRecord::Migration[8.1]
  def change
    remove_column :completion_kit_metrics, :few_shot_examples, :text
  end
end
