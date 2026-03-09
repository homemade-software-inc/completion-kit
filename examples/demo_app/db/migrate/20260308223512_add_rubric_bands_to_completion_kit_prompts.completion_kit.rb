# This migration comes from completion_kit (originally 20260308203000)
class AddRubricBandsToCompletionKitPrompts < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_prompts, :rubric_bands, :text
  end
end
