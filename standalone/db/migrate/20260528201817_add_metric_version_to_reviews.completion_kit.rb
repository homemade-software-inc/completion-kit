# This migration comes from completion_kit (originally 20260528000002)
class AddMetricVersionToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_reviews, :metric_version_id, :bigint
    add_index :completion_kit_reviews, :metric_version_id, name: "index_ck_reviews_on_metric_version_id"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_reviews
          SET metric_version_id = (
            SELECT id FROM completion_kit_metric_versions mv
            WHERE mv.metric_id = completion_kit_reviews.metric_id
              AND mv.current = #{ActiveRecord::Base.connection.quote(true)}
            LIMIT 1
          )
          WHERE metric_id IS NOT NULL
        SQL
      end
    end
  end
end
