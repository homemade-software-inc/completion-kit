# This migration comes from completion_kit (originally 20250401192930)
class CreateCompletionKitPrompts < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_prompts do |t|
      t.string :name
      t.text :description
      t.text :template
      t.string :llm_model

      t.timestamps
    end
  end
end
