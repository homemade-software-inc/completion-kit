class AddFewShotExamplesToCompletionKitMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metrics, :few_shot_examples, :text
  end
end
