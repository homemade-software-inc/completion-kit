# This migration comes from completion_kit (originally 20260507000001)
class AddDiscoveryErrorToProviderCredentials < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_provider_credentials, :discovery_error, :text
  end
end
