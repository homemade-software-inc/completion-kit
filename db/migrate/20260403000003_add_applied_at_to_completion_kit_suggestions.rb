class AddAppliedAtToCompletionKitSuggestions < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:completion_kit_suggestions, :applied_at)
    add_column :completion_kit_suggestions, :applied_at, :datetime
  end
end
