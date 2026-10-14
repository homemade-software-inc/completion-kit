# This migration comes from completion_kit (originally 20261013000001)
class DropCompletionKitMcpSessions < ActiveRecord::Migration[8.1]
  def up
    drop_table :completion_kit_mcp_sessions, if_exists: true
  end

  def down
    create_table :completion_kit_mcp_sessions do |t|
      t.string :session_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :completion_kit_mcp_sessions, :session_id, unique: true
    add_index :completion_kit_mcp_sessions, :expires_at
  end
end
