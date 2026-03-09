# This migration comes from completion_kit (originally 20260308224000)
class CreateCompletionKitMetricArchitecture < ActiveRecord::Migration[7.1]
  class LegacyMetricSet < ActiveRecord::Base
    self.table_name = "completion_kit_metric_sets"
  end

  class Prompt < ActiveRecord::Base
    self.table_name = "completion_kit_prompts"
  end

  class MetricGroup < ActiveRecord::Base
    self.table_name = "completion_kit_metric_groups"
  end

  class Metric < ActiveRecord::Base
    self.table_name = "completion_kit_metrics"
  end

  class MetricGroupMembership < ActiveRecord::Base
    self.table_name = "completion_kit_metric_group_memberships"
  end

  def up
    create_table :completion_kit_metric_groups do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    create_table :completion_kit_metrics do |t|
      t.string :name, null: false
      t.text :description
      t.text :guidance_text
      t.text :rubric_text
      t.text :rubric_bands
      t.timestamps
    end

    create_table :completion_kit_metric_group_memberships do |t|
      t.references :metric_group, null: false, foreign_key: { to_table: :completion_kit_metric_groups }
      t.references :metric, null: false, foreign_key: { to_table: :completion_kit_metrics }
      t.integer :position
      t.timestamps
    end

    create_table :completion_kit_test_result_metric_assessments do |t|
      t.references :test_result, null: false, foreign_key: { to_table: :completion_kit_test_results }
      t.references :metric, foreign_key: { to_table: :completion_kit_metrics }
      t.string :metric_name
      t.text :guidance_text
      t.text :rubric_text
      t.string :status
      t.decimal :ai_score, precision: 4, scale: 1
      t.text :ai_feedback
      t.decimal :human_score, precision: 4, scale: 1
      t.text :human_feedback
      t.string :human_reviewer_name
      t.datetime :human_reviewed_at
      t.timestamps
    end

    add_reference :completion_kit_prompts, :metric_group, foreign_key: { to_table: :completion_kit_metric_groups }

    migrate_legacy_metric_sets if table_exists?(:completion_kit_metric_sets)
  end

  def down
    remove_reference :completion_kit_prompts, :metric_group, foreign_key: { to_table: :completion_kit_metric_groups }
    drop_table :completion_kit_test_result_metric_assessments
    drop_table :completion_kit_metric_group_memberships
    drop_table :completion_kit_metrics
    drop_table :completion_kit_metric_groups
  end

  private

  def migrate_legacy_metric_sets
    LegacyMetricSet.find_each do |legacy_metric_set|
      metric_group = MetricGroup.create!(
        name: legacy_metric_set.name,
        description: "Migrated from legacy metric set."
      )

      metric = Metric.create!(
        name: legacy_metric_set.name,
        description: "Migrated from legacy metric set.",
        guidance_text: legacy_metric_set.guidance_text,
        rubric_text: legacy_metric_set.rubric_text
      )

      MetricGroupMembership.create!(
        metric_group_id: metric_group.id,
        metric_id: metric.id,
        position: 1
      )

      Prompt.where(metric_set_id: legacy_metric_set.id).update_all(metric_group_id: metric_group.id)
    end
  end
end
