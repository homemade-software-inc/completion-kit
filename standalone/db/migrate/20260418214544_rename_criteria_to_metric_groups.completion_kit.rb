# This migration comes from completion_kit (originally 20260417000001)
class RenameCriteriaToMetricGroups < ActiveRecord::Migration[8.1]
  def change
    rename_table :completion_kit_criteria, :completion_kit_metric_groups
    rename_table :completion_kit_criteria_memberships, :completion_kit_metric_group_memberships
    rename_column :completion_kit_metric_group_memberships, :criteria_id, :metric_group_id

    if index_name_exists?(:completion_kit_metric_group_memberships, "index_completion_kit_criteria_memberships_on_criteria_id")
      rename_index :completion_kit_metric_group_memberships,
        "index_completion_kit_criteria_memberships_on_criteria_id",
        "index_completion_kit_metric_group_memberships_on_metric_group_id"
    end
  end
end
