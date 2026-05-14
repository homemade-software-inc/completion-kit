module CompletionKit
  # MCP session marker — one row per active client session, kept in the
  # database so sessions survive Puma restarts, deploys, and Rails.cache
  # eviction.
  #
  # Two things to know about why every query goes through `unscoped`:
  #
  # 1. CompletionKit::ApplicationRecord applies the host app's tenant_scope as
  #    a default_scope. MCP sessions are per-CONNECTION, not per-tenant — the
  #    table has no organization_id column. Letting the tenant_scope into a
  #    session lookup turns "is this session live?" into either a SQL error
  #    (no such column) or a false negative (`WHERE 1=0`), which surfaces to
  #    the client as a spurious "Session not initialized" right after init.
  # 2. `active?` slides expires_at forward when a session is more than halfway
  #    through its TTL, so an MCP connection that keeps making calls stays
  #    alive instead of expiring on the original 1-hour wall clock.
  #
  # Expired rows are opportunistically pruned on every new session start, so
  # the table stays bounded by recent activity.
  class McpSession < ApplicationRecord
    self.table_name = "completion_kit_mcp_sessions"

    SESSION_TTL = 1.hour

    def self.start!
      prune_expired!
      unscoped.create!(session_id: SecureRandom.uuid, expires_at: SESSION_TTL.from_now).session_id
    end

    def self.active?(session_id)
      return false if session_id.blank?

      row = unscoped.where(session_id: session_id).where("expires_at > ?", Time.current).first
      return false unless row

      slide_expiry(row)
      true
    end

    def self.destroy_session(session_id)
      unscoped.where(session_id: session_id).delete_all
    end

    def self.prune_expired!
      unscoped.where("expires_at < ?", Time.current).delete_all
    end

    def self.slide_expiry(row)
      half_ttl_from_now = (SESSION_TTL / 2).from_now
      return if row.expires_at > half_ttl_from_now
      row.update_column(:expires_at, SESSION_TTL.from_now)
    end
  end
end
