class AddValidationSummaryToCompletionKitMetricVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metric_versions, :validation_summary, :text
  end
end
