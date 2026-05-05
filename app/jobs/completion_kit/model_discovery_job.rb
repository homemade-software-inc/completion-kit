require "faraday"

module CompletionKit
  class ModelDiscoveryJob < ApplicationJob
    queue_as :default

    def self.rate_limit_wait(executions)
      30 * executions
    end

    retry_on Faraday::TimeoutError,
             Faraday::ConnectionFailed,
             wait: :polynomially_longer, attempts: 5

    retry_on CompletionKit::RateLimitError,
             wait: method(:rate_limit_wait), attempts: 5

    discard_on ActiveJob::DeserializationError

    rescue_from(StandardError) do |_error|
      credential = ProviderCredential.find(arguments.first)
      credential.update_columns(discovery_status: "failed")
      credential.reload
      credential.broadcast_discovery_progress
    end

    def perform(provider_credential_id)
      credential = ProviderCredential.find_by(id: provider_credential_id)
      return unless credential

      credential.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      credential.reload
      credential.broadcast_discovery_progress

      service = ModelDiscoveryService.new(config: credential.config_hash)
      service.refresh! do |current, total|
        credential.update_columns(discovery_current: current, discovery_total: total)
        credential.reload
        credential.broadcast_discovery_progress
      end

      credential.update_columns(discovery_status: "completed", updated_at: Time.current)
      credential.reload
      credential.broadcast_discovery_complete
    end
  end
end
