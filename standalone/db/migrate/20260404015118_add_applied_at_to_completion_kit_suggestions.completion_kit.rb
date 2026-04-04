# This migration comes from completion_kit (originally 20260403000003)
class AddAppliedAtToCompletionKitSuggestions < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_suggestions, :applied_at, :datetime
  end
end
