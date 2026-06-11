module CompletionKit
  class Suggestion < ApplicationRecord
    belongs_to :run
    belongs_to :prompt

    serialize :validation_summary, coder: JSON

    validates :suggested_template, presence: true, if: :ready?

    def pending?
      status == "pending"
    end

    def failed?
      status == "failed"
    end

    def ready?
      !pending? && !failed?
    end

    def validated?
      vs = validation_summary
      vs.present? && vs["after_avg"].present?
    end

    def net_negative?
      return false unless validated?

      vs = validation_summary
      vs["after_avg"].to_f < vs["before_avg"].to_f || vs["regressed"].to_i > vs["improved"].to_i
    end
  end
end
