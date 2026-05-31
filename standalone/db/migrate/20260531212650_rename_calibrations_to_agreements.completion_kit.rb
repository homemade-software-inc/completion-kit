# This migration comes from completion_kit (originally 20260531000004)
class RenameCalibrationsToAgreements < ActiveRecord::Migration[8.1]
  CALIBRATION_INDEXES = {
    "index_ck_calibrations_on_metric_id" => "index_ck_agreements_on_metric_id",
    "index_ck_calibrations_on_metric_version_id" => "index_ck_agreements_on_metric_version_id",
    "index_ck_calibrations_on_response_id" => "index_ck_agreements_on_response_id",
    "index_ck_calibrations_on_run_id" => "index_ck_agreements_on_run_id",
    "index_ck_calibrations_on_response_metric_user" => "index_ck_agreements_on_response_metric_user"
  }.freeze

  def up
    rename_table :completion_kit_calibrations, :completion_kit_agreements
    CALIBRATION_INDEXES.each { |old_name, new_name| rename_index :completion_kit_agreements, old_name, new_name }
  end

  def down
    CALIBRATION_INDEXES.each { |old_name, new_name| rename_index :completion_kit_agreements, new_name, old_name }
    rename_table :completion_kit_agreements, :completion_kit_calibrations
  end
end
