class AddScoreFractionToCompletionKitReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_reviews, :score_fraction, :decimal, precision: 5, scale: 4
  end
end
