module CompletionKit
  class DashboardDismissal < ApplicationRecord
    FAILURE_TYPES = %w[
      CompletionKit::Run
      CompletionKit::Response
      CompletionKit::Review
    ].freeze
    DISMISSABLE_TYPES = (["CompletionKit::Metric"] + FAILURE_TYPES).freeze

    belongs_to :dismissable, polymorphic: true

    validates :dismissable_type, inclusion: { in: DISMISSABLE_TYPES }
    validates :dismissable_id, uniqueness: { scope: :dismissable_type }

    scope :metrics, lambda {
      where(dismissable_type: "CompletionKit::Metric")
        .includes(:dismissable)
        .order(Arel.sql("baseline_score DESC NULLS LAST"))
    }
    scope :failures, -> { where(dismissable_type: FAILURE_TYPES).includes(:dismissable) }
  end
end
