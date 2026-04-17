class RemoveEvaluationStepsFromMetrics < ActiveRecord::Migration[7.0]
  def change
    remove_column :completion_kit_metrics, :evaluation_steps, :text
  end
end
