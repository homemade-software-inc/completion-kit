# This migration comes from completion_kit (originally 20260501000003)
class AddStatusAndErrorToReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_reviews, :error_provider, :string
    add_column :completion_kit_reviews, :error_class, :string
    add_column :completion_kit_reviews, :error_status, :integer
    add_column :completion_kit_reviews, :error_message, :text
    add_column :completion_kit_reviews, :attempts, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_reviews
          SET status = 'succeeded'
          WHERE ai_score IS NOT NULL
        SQL

        execute <<~SQL
          UPDATE completion_kit_reviews
          SET status = 'succeeded'
          WHERE status = 'evaluated'
        SQL
      end
    end
  end
end
