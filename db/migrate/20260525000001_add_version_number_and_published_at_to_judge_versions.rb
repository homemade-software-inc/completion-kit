class AddVersionNumberAndPublishedAtToJudgeVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_judge_versions, :version_number, :integer
    add_column :completion_kit_judge_versions, :published_at, :datetime

    reversible do |dir|
      dir.up do
        jv = Class.new(ActiveRecord::Base) { self.table_name = "completion_kit_judge_versions" }
        jv.distinct.pluck(:metric_id).each do |metric_id|
          jv.where(metric_id: metric_id).order(:created_at, :id).each_with_index do |row, i|
            updates = { version_number: i + 1 }
            updates[:published_at] = row.created_at if row[:state] == "published"
            jv.where(id: row.id).update_all(updates)
          end
        end
      end
    end

    change_column_null :completion_kit_judge_versions, :version_number, false
    add_index :completion_kit_judge_versions,
              [:metric_id, :version_number],
              name: "index_ck_judge_versions_on_metric_version"
  end
end
