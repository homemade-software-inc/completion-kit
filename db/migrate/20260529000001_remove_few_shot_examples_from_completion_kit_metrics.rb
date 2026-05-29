class RemoveFewShotExamplesFromCompletionKitMetrics < ActiveRecord::Migration[8.1]
  def change
    remove_column :completion_kit_metrics, :few_shot_examples, :text
  end
end
