# This migration comes from completion_kit (originally 20260509000002)
class CreateCompletionKitTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_taggings do |t|
      t.references :tag, null: false,
                         foreign_key: { to_table: :completion_kit_tags }
      t.string :taggable_type, null: false
      t.bigint :taggable_id, null: false
      t.timestamps
    end
    add_index :completion_kit_taggings, [:taggable_type, :taggable_id]
    add_index :completion_kit_taggings,
              [:tag_id, :taggable_type, :taggable_id],
              unique: true,
              name: "idx_taggings_unique"
  end
end
