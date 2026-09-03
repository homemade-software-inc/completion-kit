module CompletionKit
  module Checks
    module NumericValue
      STRIPPED = /[,\s_]/
      CURRENCY = /\A([+-]?)[$£€]/
      NUMERIC = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/

      def self.parse(value)
        return finite(value.to_f) if value.is_a?(::Numeric)

        text = value.to_s.gsub(STRIPPED, "").sub(CURRENCY) { ::Regexp.last_match(1) }
        return nil unless NUMERIC.match?(text)

        finite(Float(text))
      end

      def self.finite(number)
        number.finite? ? number : nil
      end

      def self.format(number)
        return number.to_i.to_s if number == number.to_i

        number.to_s
      end
    end
  end
end
