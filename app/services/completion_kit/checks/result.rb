module CompletionKit
  module Checks
    Result = Data.define(:passed, :detail, :score) do
      def initialize(passed:, detail:, score: nil)
        super
      end
    end
  end
end
