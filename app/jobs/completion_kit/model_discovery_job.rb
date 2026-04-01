module CompletionKit
  class ModelDiscoveryJob < ApplicationJob
    queue_as :default

    def perform(provider_credential_id)
      credential = ProviderCredential.find_by(id: provider_credential_id)
      return unless credential

      credential.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      credential.broadcast_discovery_progress

      service = ModelDiscoveryService.new(config: credential.config_hash)
      service.refresh! do |current, total|
        credential.update_columns(discovery_current: current, discovery_total: total)
        credential.broadcast_discovery_progress
      end

      credential.update_columns(discovery_status: "completed")
      credential.broadcast_discovery_complete
    rescue StandardError
      credential.update_columns(discovery_status: "failed")
      credential.broadcast_discovery_progress
    end
  end
end
