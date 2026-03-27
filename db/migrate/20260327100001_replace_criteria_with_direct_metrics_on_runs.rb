class ReplaceCriteriaWithDirectMetricsOnRuns < ActiveRecord::Migration[7.0]
  def change
    unless table_exists?(:completion_kit_run_metrics)
      create_table :completion_kit_run_metrics do |t|
        t.references :run, null: false, foreign_key: { to_table: :completion_kit_runs }
        t.references :metric, null: false, foreign_key: { to_table: :completion_kit_metrics }
        t.integer :position
        t.timestamps
      end
    end

    if column_exists?(:completion_kit_runs, :criteria_id)
      remove_reference :completion_kit_runs, :criteria, foreign_key: { to_table: :completion_kit_criteria }
    end
  end
end
