class CreateCompletionKitJudgeVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_judge_versions do |t|
      t.references :metric,
                   null: false,
                   foreign_key: { to_table: :completion_kit_metrics, on_delete: :cascade },
                   index: { name: "index_ck_judge_versions_on_metric_id" }
      t.text :instruction
      t.text :rubric_bands
      t.boolean :current, null: false, default: true
      t.timestamps
    end

    add_index :completion_kit_judge_versions,
              [:metric_id, :current],
              name: "index_ck_judge_versions_on_metric_current"

    reversible do |dir|
      dir.up do
        metric_model = Class.new(ActiveRecord::Base) { self.table_name = "completion_kit_metrics" }
        jv_model = Class.new(ActiveRecord::Base) { self.table_name = "completion_kit_judge_versions" }
        metric_model.find_each do |m|
          jv_model.create!(metric_id: m.id, instruction: m["instruction"], rubric_bands: m["rubric_bands"], current: true)
        end
      end
    end
  end
end
