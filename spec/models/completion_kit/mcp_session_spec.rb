require "rails_helper"

RSpec.describe CompletionKit::McpSession do
  describe ".start!" do
    it "creates a session row and returns its id" do
      expect { @id = described_class.start! }.to change(described_class, :count).by(1)
      expect(@id).to be_a(String).and be_present
      expect(described_class.find_by(session_id: @id).expires_at).to be_within(5.seconds).of(described_class::SESSION_TTL.from_now)
    end

    it "prunes expired sessions on start" do
      expired = described_class.create!(session_id: SecureRandom.uuid, expires_at: 1.minute.ago)
      described_class.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.from_now)

      new_id = described_class.start!

      expect(described_class.exists?(expired.id)).to eq(false)
      expect(described_class.active?(new_id)).to eq(true)
      expect(described_class.count).to eq(2)
    end
  end

  describe ".active?" do
    it "is false for nil and blank ids" do
      expect(described_class.active?(nil)).to eq(false)
      expect(described_class.active?("")).to eq(false)
    end

    it "is false for an unknown id" do
      expect(described_class.active?("does-not-exist")).to eq(false)
    end

    it "is true for a live session" do
      id = described_class.start!
      expect(described_class.active?(id)).to eq(true)
    end

    it "is false once the session is past its expires_at" do
      id = SecureRandom.uuid
      described_class.create!(session_id: id, expires_at: 1.minute.ago)
      expect(described_class.active?(id)).to eq(false)
    end

    it "slides expires_at forward when the session is past the halfway mark" do
      id = SecureRandom.uuid
      ttl = described_class::SESSION_TTL
      stale = described_class.create!(session_id: id, expires_at: (ttl / 4).from_now)

      described_class.active?(id)

      expect(stale.reload.expires_at).to be_within(5.seconds).of(ttl.from_now)
    end

    it "does not slide expires_at when the session has plenty of life left" do
      id = SecureRandom.uuid
      ttl = described_class::SESSION_TTL
      fresh = described_class.create!(session_id: id, expires_at: (ttl - 30.seconds).from_now)
      original = fresh.expires_at

      described_class.active?(id)

      expect(fresh.reload.expires_at).to be_within(5.seconds).of(original)
    end
  end

  describe "host-app tenant_scope isolation" do
    around do |example|
      original = CompletionKit.config.tenant_scope
      CompletionKit.config.tenant_scope = -> { where("organization_id = ?", 999_999) }
      example.run
    ensure
      CompletionKit.config.tenant_scope = original
    end

    it "creates and looks up sessions even when the host app's tenant_scope filters by a column the sessions table doesn't have" do
      id = described_class.start!
      expect(described_class.active?(id)).to eq(true)
      expect { described_class.destroy_session(id) }.to change(described_class, :count).by(-1)
    end
  end

  describe ".destroy_session" do
    it "removes the row" do
      id = described_class.start!
      expect { described_class.destroy_session(id) }.to change(described_class, :count).by(-1)
      expect(described_class.active?(id)).to eq(false)
    end

    it "is a no-op for an unknown id" do
      expect { described_class.destroy_session("nope") }.not_to change(described_class, :count)
    end
  end

  describe ".prune_expired!" do
    it "deletes only the past-due rows" do
      live = described_class.create!(session_id: SecureRandom.uuid, expires_at: 1.hour.from_now)
      stale = described_class.create!(session_id: SecureRandom.uuid, expires_at: 1.minute.ago)

      described_class.prune_expired!

      expect(described_class.exists?(live.id)).to eq(true)
      expect(described_class.exists?(stale.id)).to eq(false)
    end
  end
end
