# This migration comes from completion_kit (originally 20260531000001)
class AddValidationSummaryToCompletionKitMetricVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_metric_versions, :validation_summary, :text
  end
end
