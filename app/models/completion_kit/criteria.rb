module CompletionKit
  class Criteria < ApplicationRecord
    self.table_name = "completion_kit_criteria"

    has_many :criteria_memberships, -> { order(:position, :id) }, dependent: :destroy
    has_many :metrics, through: :criteria_memberships

    validates :name, presence: true

    def ordered_metrics
      criteria_memberships.includes(:metric).map(&:metric).compact
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
