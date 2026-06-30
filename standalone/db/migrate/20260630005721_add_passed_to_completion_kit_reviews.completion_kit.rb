# This migration comes from completion_kit (originally 20260629000003)
class AddPassedToCompletionKitReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_reviews, :passed, :boolean
  end
end
