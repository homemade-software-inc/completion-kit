class AddDiscoveryColumnsToCompletionKitProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_provider_credentials, :discovery_status, :string
    add_column :completion_kit_provider_credentials, :discovery_current, :integer, default: 0
    add_column :completion_kit_provider_credentials, :discovery_total, :integer, default: 0
  end
end
