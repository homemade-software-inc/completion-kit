# This migration comes from completion_kit (originally 20260308200020)
class CreateCompletionKitProviderCredentials < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_provider_credentials do |t|
      t.string :provider, null: false
      t.text :api_key
      t.text :api_endpoint

      t.timestamps
    end

    add_index :completion_kit_provider_credentials, :provider, unique: true
  end
end
