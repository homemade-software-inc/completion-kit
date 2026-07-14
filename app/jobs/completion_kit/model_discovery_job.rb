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

    rescue_from(StandardError) do |error|
      if error.is_a?(CompletionKit::ModelDiscoveryService::DiscoveryError)
        Rails.error.report(error, handled: true, context: { job: self.class.name, provider_credential_id: arguments.first })
      end
      credential = ProviderCredential.find_by(id: arguments.first)
      next unless credential
      credential.update_columns(discovery_status: "failed", discovery_error: error.message.to_s.truncate(500))
      credential.reload
      credential.broadcast_discovery_progress
    end

    def perform(provider_credential_id, force: false)
      credential = ProviderCredential.find_by(id: provider_credential_id)
      return unless credential

      credential.update_columns(
        discovery_status: "discovering",
        discovery_current: 0,
        discovery_total: 0,
        discovery_error: nil
      )
      credential.reload
      credential.broadcast_discovery_progress

      service = ModelDiscoveryService.new(config: credential.config_hash)
      service.refresh!(force: force) do |current, total|
        credential.update_columns(discovery_current: current, discovery_total: total)
        credential.reload
        credential.broadcast_discovery_progress
      end

      credential.update_columns(
        discovery_status: "completed",
        discovery_error: nil,
        catalog_model_count: service.catalog_model_count,
        updated_at: Time.current
      )
      credential.reload
      credential.broadcast_discovery_complete
    end
  end
end
