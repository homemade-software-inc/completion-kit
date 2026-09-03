module CompletionKit
  module Checks
    module Flag
      def self.on?(config, key)
        ActiveModel::Type::Boolean.new.cast(config[key]) == true
      end
    end
  end
end
