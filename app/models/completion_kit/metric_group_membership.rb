module CompletionKit
  class MetricGroupMembership < ApplicationRecord
    belongs_to :metric_group
    belongs_to :metric

    validates :metric_id, uniqueness: { scope: :metric_group_id }

    before_validation :set_default_position

    private

    def set_default_position
      return if position.present? || metric_group.blank?

      self.position = metric_group.metric_group_memberships.maximum(:position).to_i + 1
    end
  end
end
