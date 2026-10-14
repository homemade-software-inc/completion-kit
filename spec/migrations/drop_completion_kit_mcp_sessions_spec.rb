require "rails_helper"
require File.expand_path("../../db/migrate/20261013000001_drop_completion_kit_mcp_sessions.rb", __dir__)

RSpec.describe DropCompletionKitMcpSessions do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new.tap { |m| m.verbose = false } }

  after { connection.drop_table(:completion_kit_mcp_sessions, if_exists: true) }

  it "leaves the test schema without the table" do
    expect(connection.table_exists?(:completion_kit_mcp_sessions)).to be false
  end

  it "drops the table on the way up" do
    migration.migrate(:down)

    migration.migrate(:up)

    expect(connection.table_exists?(:completion_kit_mcp_sessions)).to be false
  end

  it "does nothing on the way up when the table is already gone" do
    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.table_exists?(:completion_kit_mcp_sessions)).to be false
  end

  it "recreates the table and its indexes on the way down" do
    migration.migrate(:down)

    columns = connection.columns(:completion_kit_mcp_sessions).to_h { |c| [c.name, c] }
    expect(columns.keys).to contain_exactly("id", "session_id", "expires_at", "created_at", "updated_at")
    expect(columns.values_at("session_id", "expires_at", "created_at", "updated_at").map(&:null)).to all(be false)
    expect(columns["session_id"].type).to eq(:string)
    expect(columns["expires_at"].type).to eq(:datetime)

    indexes = connection.indexes(:completion_kit_mcp_sessions).to_h { |i| [i.columns, i] }
    expect(indexes.keys).to contain_exactly(["session_id"], ["expires_at"])
    expect(indexes[["session_id"]].unique).to be true
    expect(indexes[["expires_at"]].unique).to be false
  end
end
