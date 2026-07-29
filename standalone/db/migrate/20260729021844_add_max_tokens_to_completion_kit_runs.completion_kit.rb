# This migration comes from completion_kit (originally 20260728000001)
class AddMaxTokensToCompletionKitRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_runs, :max_tokens, :integer
  end
end
