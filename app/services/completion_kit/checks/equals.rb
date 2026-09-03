module CompletionKit
  module Checks
    class Equals
      def call(target, config)
        expected, actual = Textual.operands(target, config)

        match = if Flag.on?(config, "case_sensitive")
          actual == expected
        else
          actual.casecmp?(expected)
        end

        if match
          Result.new(passed: true, detail: "equals #{expected.inspect}")
        else
          Result.new(passed: false, detail: "#{actual.inspect} != #{expected.inspect}")
        end
      end
    end
  end
end
