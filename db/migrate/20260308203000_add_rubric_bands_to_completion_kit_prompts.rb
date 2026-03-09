class AddRubricBandsToCompletionKitPrompts < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_prompts, :rubric_bands, :text
  end
end
