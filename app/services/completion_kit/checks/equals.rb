module CompletionKit
  module Checks
    class Equals
      def call(target, config)
        actual = target.to_s
        expected = config["value"].to_s
        if config["trim"] == true
          actual = actual.strip
          expected = expected.strip
        end

        match = if config["case_sensitive"] == true
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
