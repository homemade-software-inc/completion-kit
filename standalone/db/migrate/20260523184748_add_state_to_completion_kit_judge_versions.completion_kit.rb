# This migration comes from completion_kit (originally 20260523000002)
class AddStateToCompletionKitJudgeVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_judge_versions, :state, :string, null: false, default: "published"
    add_column :completion_kit_judge_versions, :source, :string

    reversible do |dir|
      dir.up do
        execute "UPDATE completion_kit_judge_versions SET state = 'published'"
      end
    end

    add_index :completion_kit_judge_versions, [:metric_id, :state],
              name: "index_ck_judge_versions_on_metric_state"
  end
end
