ActiveRecord::Schema.define do
  create_table :completion_kit_tenanted_things, force: true do |t|
    t.string :label
    t.string :category
    t.integer :organization_id
    t.integer :parent_id
    t.timestamps
  end
end

module CompletionKit
  class TenantedThing < ApplicationRecord
    self.table_name = "completion_kit_tenanted_things"
    has_many :children, class_name: "CompletionKit::TenantedChild", foreign_key: :parent_id
    validates :label, tenant_scoped_uniqueness: { allow_nil: true }
  end

  class ScopedTenantedThing < ApplicationRecord
    self.table_name = "completion_kit_tenanted_things"
    validates :category, tenant_scoped_uniqueness: { scope: :label, allow_nil: true }
  end

  class TenantedChild < ApplicationRecord
    self.table_name = "completion_kit_tenanted_things"
    belongs_to :parent, class_name: "CompletionKit::TenantedThing"
  end
end

module TenantScopingHelpers
  def with_tenant(org_id)
    previous = Thread.current[:ck_org_id]
    Thread.current[:ck_org_id] = org_id
    yield
  ensure
    Thread.current[:ck_org_id] = previous
  end

  def configure_tenant_scope
    CompletionKit.config.tenant_scope = -> {
      org = Thread.current[:ck_org_id]
      org ? where(organization_id: org) : where("1=0")
    }
    CompletionKit.config.tenant_scope_columns = [:organization_id]
  end

  def reset_tenant_scope
    CompletionKit.config.tenant_scope = nil
    CompletionKit.config.tenant_scope_columns = []
    Thread.current[:ck_org_id] = nil
  end
end

RSpec.configure do |config|
  config.include TenantScopingHelpers
  config.before(:each) { reset_tenant_scope }
  config.after(:each) { reset_tenant_scope }
end
