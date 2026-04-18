module CompletionKit
  class MetricGroup < ApplicationRecord
    self.table_name = "completion_kit_metric_groups"

    has_many :metric_group_memberships, -> { order(:position, :id) }, dependent: :destroy
    has_many :metrics, through: :metric_group_memberships

    validates :name, presence: true

    def ordered_metrics
      metric_group_memberships.includes(:metric).map(&:metric).compact
    end

    def as_json(options = {})
      {
        id: id, name: name, description: description,
        created_at: created_at, updated_at: updated_at,
        metric_ids: metric_ids
      }
    end
  end
end
