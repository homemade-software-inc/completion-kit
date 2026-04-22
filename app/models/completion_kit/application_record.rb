module CompletionKit
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    TenantScopedUniquenessValidator = CompletionKit::TenantScopedUniquenessValidator

    default_scope do
      scope_proc = CompletionKit.config.tenant_scope
      scope_proc ? instance_exec(&scope_proc) : all
    end
  end
end
