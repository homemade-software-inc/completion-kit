module CompletionKit
  class Criteria < ApplicationRecord
    self.table_name = "completion_kit_criteria"

    has_many :criteria_memberships, -> { order(:position, :id) }, dependent: :destroy
    has_many :metrics, through: :criteria_memberships
    has_many :runs, dependent: :nullify

    validates :name, presence: true

    def ordered_metrics
      criteria_memberships.includes(:metric).map(&:metric).compact
    end
  end
end
