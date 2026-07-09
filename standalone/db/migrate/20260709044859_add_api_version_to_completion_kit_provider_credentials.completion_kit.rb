# This migration comes from completion_kit (originally 20260708000001)
class AddApiVersionToCompletionKitProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_provider_credentials, :api_version, :string
  end
end
