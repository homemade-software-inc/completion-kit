class CreateCompletionKitCalibrations < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_calibrations do |t|
      t.references :run,
                   null: false,
                   foreign_key: { to_table: :completion_kit_runs, on_delete: :cascade },
                   index: { name: "index_ck_calibrations_on_run_id" }
      t.references :response,
                   null: false,
                   foreign_key: { to_table: :completion_kit_responses, on_delete: :cascade },
                   index: { name: "index_ck_calibrations_on_response_id" }
      t.references :metric,
                   null: false,
                   foreign_key: { to_table: :completion_kit_metrics, on_delete: :cascade },
                   index: { name: "index_ck_calibrations_on_metric_id" }
      t.references :judge_version,
                   null: false,
                   foreign_key: { to_table: :completion_kit_judge_versions, on_delete: :cascade },
                   index: { name: "index_ck_calibrations_on_judge_version_id" }
      t.string :verdict, null: false
      t.string :created_by
      t.decimal :corrected_score, precision: 4, scale: 1
      t.text :note
      t.timestamps
    end

    add_index :completion_kit_calibrations,
              [:response_id, :metric_id, :created_by],
              unique: true,
              name: "index_ck_calibrations_on_response_metric_user"
  end
end
