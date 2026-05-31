# This migration comes from completion_kit (originally 20260531000002)
class BackfillReviewMetricVersions < ActiveRecord::Migration[8.1]
  def up
    quoted_true = ActiveRecord::Base.connection.quote(true)
    now = ActiveRecord::Base.connection.quote(Time.current)

    execute <<~SQL
      INSERT INTO completion_kit_metric_versions
        (metric_id, instruction, rubric_bands, current, state, version_number, published_at, created_at, updated_at)
      SELECT m.id, m.instruction, m.rubric_bands, #{quoted_true}, 'published', 1, #{now}, #{now}, #{now}
      FROM completion_kit_metrics m
      WHERE NOT EXISTS (
        SELECT 1 FROM completion_kit_metric_versions mv WHERE mv.metric_id = m.id
      )
    SQL

    execute <<~SQL
      UPDATE completion_kit_reviews
      SET metric_version_id = (
        SELECT mv.id FROM completion_kit_metric_versions mv
        WHERE mv.metric_id = completion_kit_reviews.metric_id AND mv.current = #{quoted_true}
        LIMIT 1
      )
      WHERE metric_id IS NOT NULL
        AND (
          metric_version_id IS NULL
          OR metric_version_id NOT IN (SELECT id FROM completion_kit_metric_versions)
        )
    SQL
  end

  def down
  end
end
