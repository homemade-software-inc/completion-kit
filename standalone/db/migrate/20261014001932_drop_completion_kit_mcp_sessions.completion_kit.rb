# This migration comes from completion_kit (originally 20261013000001)
class DropCompletionKitMcpSessions < ActiveRecord::Migration[8.1]
  def change
    drop_table :completion_kit_mcp_sessions, if_exists: true do |t|
      t.string :session_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
      t.index :session_id, unique: true
      t.index :expires_at
    end
  end
end
