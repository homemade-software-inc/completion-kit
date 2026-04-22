require "rails_helper"

RSpec.describe CompletionKit::TenantScopedUniquenessValidator do
  describe "with empty tenant_scope_columns" do
    it "behaves like plain uniqueness" do
      CompletionKit::TenantedThing.create!(label: "same", organization_id: 1)
      dup = CompletionKit::TenantedThing.new(label: "same", organization_id: 2)
      expect(dup).not_to be_valid
      expect(dup.errors[:label]).to be_present
    end

    it "honors a declared :scope option" do
      CompletionKit::ScopedTenantedThing.create!(label: "L", category: "X", organization_id: 1)
      same_label_diff_cat = CompletionKit::ScopedTenantedThing.new(label: "L", category: "Y", organization_id: 1)
      expect(same_label_diff_cat).to be_valid
      same_label_same_cat = CompletionKit::ScopedTenantedThing.new(label: "L", category: "X", organization_id: 2)
      expect(same_label_same_cat).not_to be_valid
    end
  end

  describe "with tenant_scope_columns set" do
    before { CompletionKit.config.tenant_scope_columns = [:organization_id] }

    it "allows the same value across different tenants" do
      CompletionKit::TenantedThing.create!(label: "shared", organization_id: 1)
      dup = CompletionKit::TenantedThing.new(label: "shared", organization_id: 2)
      expect(dup).to be_valid
    end

    it "rejects the same value within a tenant" do
      CompletionKit::TenantedThing.create!(label: "shared", organization_id: 1)
      dup = CompletionKit::TenantedThing.new(label: "shared", organization_id: 1)
      expect(dup).not_to be_valid
    end

    it "stacks the host tenant columns on top of a declared :scope" do
      CompletionKit::ScopedTenantedThing.create!(label: "L", category: "C", organization_id: 1)

      cross_tenant_same = CompletionKit::ScopedTenantedThing.new(label: "L", category: "C", organization_id: 2)
      expect(cross_tenant_same).to be_valid

      same_tenant_diff_label = CompletionKit::ScopedTenantedThing.new(label: "M", category: "C", organization_id: 1)
      expect(same_tenant_diff_label).to be_valid

      same_tenant_same = CompletionKit::ScopedTenantedThing.new(label: "L", category: "C", organization_id: 1)
      expect(same_tenant_same).not_to be_valid
    end
  end

  describe "config toggling between calls" do
    it "picks up tenant_scope_columns changes without class reload" do
      CompletionKit::TenantedThing.create!(label: "t", organization_id: 1)

      CompletionKit.config.tenant_scope_columns = []
      expect(CompletionKit::TenantedThing.new(label: "t", organization_id: 2)).not_to be_valid

      CompletionKit.config.tenant_scope_columns = [:organization_id]
      expect(CompletionKit::TenantedThing.new(label: "t", organization_id: 2)).to be_valid
    end
  end
end
