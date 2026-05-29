module CompletionKit
  module HasJobStatus
    extend ActiveSupport::Concern

    STATUSES = %w[pending retrying succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    included do
      validates :status, inclusion: { in: STATUSES }
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def succeeded?
      status == "succeeded"
    end

    def error_payload
      return nil if error_class.blank?
      { provider: error_provider, class: error_class, status: error_status, message: error_message }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
