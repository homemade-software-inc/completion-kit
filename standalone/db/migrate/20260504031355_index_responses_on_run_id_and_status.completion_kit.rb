# This migration comes from completion_kit (originally 20260501000002)
class IndexResponsesOnRunIdAndStatus < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    options = { if_not_exists: true }
    options[:algorithm] = :concurrently unless connection.adapter_name == "SQLite"
    add_index :completion_kit_responses, [:run_id, :status], **options
  end
end
