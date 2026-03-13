module CompletionKit
  class CriteriaMembership < ApplicationRecord
    self.table_name = "completion_kit_criteria_memberships"

    belongs_to :criteria, class_name: "CompletionKit::Criteria", foreign_key: "criteria_id"
    belongs_to :metric

    validates :metric_id, uniqueness: { scope: :criteria_id }

    before_validation :set_default_position

    private

    def set_default_position
      return if position.present? || criteria.blank?

      self.position = criteria.criteria_memberships.maximum(:position).to_i + 1
    end
  end
end
