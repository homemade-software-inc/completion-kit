class AddApiVersionToCompletionKitProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_provider_credentials, :api_version, :string
  end
end
