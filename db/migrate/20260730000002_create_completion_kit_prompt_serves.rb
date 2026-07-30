class CreateCompletionKitPromptServes < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_prompt_serves do |t|
      t.integer :prompt_id
      t.string :family_key, null: false
      t.date :served_on, null: false
      t.integer :serve_count, null: false, default: 0
      t.datetime :last_served_at
      t.timestamps
    end

    add_index :completion_kit_prompt_serves, [:prompt_id, :served_on],
              unique: true, name: "index_ck_prompt_serves_on_prompt_and_day"
    add_index :completion_kit_prompt_serves, [:family_key, :served_on],
              name: "index_ck_prompt_serves_on_family_and_day"
  end
end
