class CreateCompletionKitCalibrations < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_calibrations do |t|
      t.references :run, null: false, foreign_key: { to_table: :completion_kit_runs }
      t.references :response, null: false, foreign_key: { to_table: :completion_kit_responses }
      t.references :metric, foreign_key: { to_table: :completion_kit_metrics }
      t.string :anonymous_id, null: false # browser-generated UUID for anonymous feedback
      t.string :verdict, null: false # agree, disagree, borderline
      t.decimal :corrected_score, precision: 3, scale: 2
      t.text :note
      t.integer :judge_version_id # nullable for now
      t.timestamps
    end
    # Unique per run/response/metric/anonymous_id so users can update their own verdicts
    add_index :completion_kit_calibrations, [:run_id, :response_id, :metric_id, :anonymous_id], unique: true, name: "index_calibrations_unique"
  end
end