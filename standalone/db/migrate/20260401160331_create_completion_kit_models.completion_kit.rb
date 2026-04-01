# This migration comes from completion_kit (originally 20260329000001)
class CreateCompletionKitModels < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_models do |t|
      t.string :provider, null: false
      t.string :model_id, null: false
      t.string :display_name
      t.string :status, null: false, default: "active"
      t.boolean :supports_generation
      t.boolean :supports_judging
      t.text :generation_error
      t.text :judging_error
      t.datetime :probed_at
      t.datetime :discovered_at
      t.datetime :retired_at
      t.timestamps
    end

    add_index :completion_kit_models, [:provider, :model_id], unique: true
  end
end
