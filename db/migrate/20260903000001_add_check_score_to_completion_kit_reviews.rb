class AddCheckScoreToCompletionKitReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_reviews, :check_score, :decimal, precision: 5, scale: 4
  end
end
