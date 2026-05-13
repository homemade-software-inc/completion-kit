class CreateCompletionKitMcpSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :completion_kit_mcp_sessions do |t|
      t.string :session_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :completion_kit_mcp_sessions, :session_id, unique: true
    add_index :completion_kit_mcp_sessions, :expires_at
  end
end
