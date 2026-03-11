module CompletionKit
  class MetricGroup < ApplicationRecord
    has_many :metric_group_memberships, -> { order(:position, :id) }, dependent: :destroy
    has_many :metrics, through: :metric_group_memberships
    has_many :runs, dependent: :nullify

    validates :name, presence: true

    def ordered_metrics
      metric_group_memberships.includes(:metric).map(&:metric).compact
    end
  end
end
