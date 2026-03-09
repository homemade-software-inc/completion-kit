class AddEvalDslFields < ActiveRecord::Migration[7.0]
  def change
    add_column :completion_kit_metrics, :key, :string
    add_index :completion_kit_metrics, :key, unique: true

    add_column :completion_kit_test_runs, :source, :string, default: "ui"
    add_column :completion_kit_test_runs, :eval_name, :string
  end
end
