# This migration comes from completion_kit (originally 20260715000001)
class DedupeAndUniqueIndexMetricVersions < ActiveRecord::Migration[8.1]
  class MetricVersion < ActiveRecord::Base
    self.table_name = "completion_kit_metric_versions"
  end

  class Review < ActiveRecord::Base
    self.table_name = "completion_kit_reviews"
  end

  class Agreement < ActiveRecord::Base
    self.table_name = "completion_kit_agreements"
  end

  def up
    collapse_duplicate_versions
    collapse_extra_current

    remove_index :completion_kit_metric_versions, name: "index_ck_metric_versions_on_metric_vnum", if_exists: true
    add_index :completion_kit_metric_versions, [:metric_id, :version_number],
      unique: true, name: "index_ck_metric_versions_on_metric_vnum"
  end

  def down
    remove_index :completion_kit_metric_versions, name: "index_ck_metric_versions_on_metric_vnum", if_exists: true
    add_index :completion_kit_metric_versions, [:metric_id, :version_number],
      name: "index_ck_metric_versions_on_metric_vnum"
  end

  private

  def collapse_duplicate_versions
    MetricVersion.order(:id).pluck(:id, :metric_id, :version_number)
                 .group_by { |(_, metric_id, version_number)| [metric_id, version_number] }
                 .each_value do |group|
      next if group.size < 2

      canonical = group.first.first
      losers = group.drop(1).map(&:first)
      Review.where(metric_version_id: losers).update_all(metric_version_id: canonical)
      Agreement.where(metric_version_id: losers).update_all(metric_version_id: canonical)
      MetricVersion.where(id: losers).delete_all
    end
  end

  def collapse_extra_current
    MetricVersion.where(current: true)
                 .order(metric_id: :asc, version_number: :desc, id: :desc)
                 .pluck(:id, :metric_id)
                 .group_by { |(_, metric_id)| metric_id }
                 .each_value do |rows|
      next if rows.size < 2

      MetricVersion.where(id: rows.drop(1).map(&:first)).update_all(current: false)
    end
  end
end
