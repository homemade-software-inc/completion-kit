class RenameJudgeVersionToMetricVersion < ActiveRecord::Migration[8.1]
  def change
    rename_table :completion_kit_judge_versions, :completion_kit_metric_versions
    rename_column :completion_kit_calibrations, :judge_version_id, :metric_version_id

    rename_index :completion_kit_metric_versions,
                 "index_ck_judge_versions_on_metric_id",
                 "index_ck_metric_versions_on_metric_id"
    rename_index :completion_kit_metric_versions,
                 "index_ck_judge_versions_on_metric_current",
                 "index_ck_metric_versions_on_metric_current"
    rename_index :completion_kit_metric_versions,
                 "index_ck_judge_versions_on_metric_state",
                 "index_ck_metric_versions_on_metric_state"
    rename_index :completion_kit_metric_versions,
                 "index_ck_judge_versions_on_metric_version",
                 "index_ck_metric_versions_on_metric_vnum"
    rename_index :completion_kit_calibrations,
                 "index_ck_calibrations_on_judge_version_id",
                 "index_ck_calibrations_on_metric_version_id"
  end
end
