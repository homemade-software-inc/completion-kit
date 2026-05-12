module CompletionKit
  class Model < ApplicationRecord
    STATUSES = %w[active retired failed].freeze

    validates :provider, presence: true
    validates :model_id, presence: true, tenant_scoped_uniqueness: { scope: :provider }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }
    scope :for_generation, -> { active.where(supports_generation: true) }
    # Includes models not yet confirmed as judges (supports_judging: nil) — worth
    # a try, and a successful run flips them to confirmed. Only models known to be
    # bad judges (false) are excluded.
    scope :for_judging, -> { active.where(supports_judging: [true, nil]) }
  end
end
