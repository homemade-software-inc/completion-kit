class CreateCompletionKitTags < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_tags do |t|
      t.string :name, null: false
      t.string :color, null: false
      t.timestamps
    end
    add_index :completion_kit_tags, :name, unique: true
  end
end
