class CreateCompletionKitSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_suggestions do |t|
      t.references :run, null: false
      t.references :prompt, null: false
      t.text :reasoning
      t.text :suggested_template
      t.text :original_template
      t.timestamps
    end
  end
end
