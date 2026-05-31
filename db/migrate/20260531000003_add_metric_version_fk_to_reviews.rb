class AddMetricVersionFkToReviews < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :completion_kit_reviews, :completion_kit_metric_versions,
                    column: :metric_version_id, on_delete: :nullify
  end
end
