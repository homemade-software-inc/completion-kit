# This migration comes from completion_kit (originally 20260611000001)
class AddValidationToCompletionKitSuggestions < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_suggestions, :validation_summary, :text
    add_column :completion_kit_suggestions, :status, :string, default: "ready", null: false
  end
end
