require "rails_helper"

RSpec.describe CompletionKit::ApplicationRecord do
  describe "Configuration defaults" do
    it "tenant_scope defaults to nil" do
      expect(CompletionKit::Configuration.new.tenant_scope).to be_nil
    end

    it "tenant_scope_columns defaults to []" do
      expect(CompletionKit::Configuration.new.tenant_scope_columns).to eq([])
    end
  end

  describe "with no tenant_scope configured" do
    it "applies no implicit scope" do
      a = CompletionKit::TenantedThing.create!(label: "a", organization_id: 1)
      b = CompletionKit::TenantedThing.create!(label: "b", organization_id: 2)
      expect(CompletionKit::TenantedThing.all).to contain_exactly(a, b)
    end
  end

  describe "with tenant_scope configured" do
    before { configure_tenant_scope }

    it "filters queries by the per-call tenant" do
      a = with_tenant(1) { CompletionKit::TenantedThing.create!(label: "a") }
      b = with_tenant(2) { CompletionKit::TenantedThing.create!(label: "b") }

      with_tenant(1) { expect(CompletionKit::TenantedThing.all).to contain_exactly(a) }
      with_tenant(2) { expect(CompletionKit::TenantedThing.all).to contain_exactly(b) }
    end

    it "auto-assigns the tenant column on new records from the scope equality" do
      with_tenant(42) do
        expect(CompletionKit::TenantedThing.new(label: "x").organization_id).to eq(42)
      end
    end

    it "fails closed when the tenant is nil" do
      with_tenant(1) { CompletionKit::TenantedThing.create!(label: "exists") }
      with_tenant(nil) { expect(CompletionKit::TenantedThing.all.to_a).to eq([]) }
    end

    it "unscoped bypasses the scope" do
      with_tenant(1) { CompletionKit::TenantedThing.create!(label: "one") }
      with_tenant(2) { CompletionKit::TenantedThing.create!(label: "two") }
      with_tenant(nil) { expect(CompletionKit::TenantedThing.unscoped.count).to eq(2) }
    end

    it "find raises RecordNotFound for a foreign-tenant id" do
      record = with_tenant(1) { CompletionKit::TenantedThing.create!(label: "own") }
      with_tenant(2) do
        expect { CompletionKit::TenantedThing.find(record.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "respects the scope across engine-table associations" do
      parent = with_tenant(1) { CompletionKit::TenantedThing.create!(label: "parent") }
      CompletionKit::TenantedChild.unscoped.create!(label: "own", parent_id: parent.id, organization_id: 1)
      CompletionKit::TenantedChild.unscoped.create!(label: "foreign", parent_id: parent.id, organization_id: 2)

      with_tenant(1) { expect(parent.children.pluck(:label)).to contain_exactly("own") }
    end

    it "picks up tenant_scope changes between examples" do
      CompletionKit.config.tenant_scope = -> { where(organization_id: 99) }
      CompletionKit::TenantedThing.unscoped.create!(label: "x", organization_id: 99)
      CompletionKit::TenantedThing.unscoped.create!(label: "y", organization_id: 1)

      expect(CompletionKit::TenantedThing.pluck(:label)).to contain_exactly("x")
    end
  end
end
