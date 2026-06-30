class AddCheckTypeToCompletionKitMetricVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metric_versions, :metric_type, :string, null: false, default: "llm_judge"
    add_column :completion_kit_metric_versions, :check_config, :text
  end
end
