class AddCatalogModelCountToCompletionKitProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_provider_credentials, :catalog_model_count, :integer
  end
end
