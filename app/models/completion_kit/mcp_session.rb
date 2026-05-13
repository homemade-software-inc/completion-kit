module CompletionKit
  # MCP session marker — one row per active client session, kept in the
  # database so sessions survive Puma restarts, deploys, and Rails.cache
  # eviction. Expired rows are opportunistically pruned on every new
  # session start, so the table stays bounded by recent activity.
  class McpSession < ApplicationRecord
    self.table_name = "completion_kit_mcp_sessions"

    SESSION_TTL = 1.hour

    def self.start!
      prune_expired!
      create!(session_id: SecureRandom.uuid, expires_at: SESSION_TTL.from_now).session_id
    end

    def self.active?(session_id)
      return false if session_id.blank?
      where(session_id: session_id).where("expires_at > ?", Time.current).exists?
    end

    def self.destroy_session(session_id)
      where(session_id: session_id).delete_all
    end

    def self.prune_expired!
      where("expires_at < ?", Time.current).delete_all
    end
  end
end
