class IndexReviewsOnResponseIdAndStatus < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :completion_kit_reviews, [:response_id, :status],
              algorithm: :concurrently,
              if_not_exists: true
  end
end
