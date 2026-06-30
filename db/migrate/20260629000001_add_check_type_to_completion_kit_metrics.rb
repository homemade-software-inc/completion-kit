class AddCheckTypeToCompletionKitMetrics < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metrics, :metric_type, :string, null: false, default: "llm_judge"
    add_column :completion_kit_metrics, :check_config, :text
  end
end
