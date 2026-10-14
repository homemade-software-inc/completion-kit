module CompletionKit
  module Checks
    module Flag
      def self.on?(config, key)
        cast(config[key])
      end

      def self.cast(value)
        ActiveModel::Type::Boolean.new.cast(value) == true
      end
    end
  end
end
