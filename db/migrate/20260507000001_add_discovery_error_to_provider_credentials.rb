class AddDiscoveryErrorToProviderCredentials < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_provider_credentials, :discovery_error, :text
  end
end
