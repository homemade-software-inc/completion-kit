module CompletionKit
  class TenantScopedUniquenessValidator < ActiveRecord::Validations::UniquenessValidator
    def validate_each(record, attribute, value)
      extra = Array(CompletionKit.config.tenant_scope_columns)
      return super if extra.empty? && options[:scope].nil?

      merged = options.merge(
        scope: Array(options[:scope]) + extra,
        attributes: [attribute],
        class: @klass
      )
      self.class.superclass.new(merged).validate(record)
    end
  end
end
