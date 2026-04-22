module CompletionKit
  class Model < ApplicationRecord
    STATUSES = %w[active retired failed].freeze

    validates :provider, presence: true
    validates :model_id, presence: true, tenant_scoped_uniqueness: { scope: :provider }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }
    scope :for_generation, -> { active.where(supports_generation: true) }
    scope :for_judging, -> { active.where(supports_judging: true) }
  end
end
