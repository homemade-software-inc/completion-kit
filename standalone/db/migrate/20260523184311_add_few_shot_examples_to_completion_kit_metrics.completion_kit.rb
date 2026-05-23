# This migration comes from completion_kit (originally 20260523000001)
class AddFewShotExamplesToCompletionKitMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metrics, :few_shot_examples, :text
  end
end
