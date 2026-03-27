# This migration comes from completion_kit (originally 20260327100001)
class ReplaceCriteriaWithDirectMetricsOnRuns < ActiveRecord::Migration[7.0]
  def change
    create_table :completion_kit_run_metrics do |t|
      t.references :run, null: false, foreign_key: { to_table: :completion_kit_runs }
      t.references :metric, null: false, foreign_key: { to_table: :completion_kit_metrics }
      t.integer :position
      t.timestamps
    end

    remove_reference :completion_kit_runs, :criteria, foreign_key: { to_table: :completion_kit_criteria }
  end
end
