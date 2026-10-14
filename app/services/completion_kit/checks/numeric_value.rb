module CompletionKit
  module Checks
    module NumericValue
      STRIPPED = /[,\s_   ]/
      CURRENCY = /\A([+-]?)[$£€]/
      NUMERIC = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/
      PREVIEW_LENGTH = 40

      def self.parse(value)
        return finite(value.to_f) if value.is_a?(::Numeric)

        text = clean(value)
        return nil unless NUMERIC.match?(text)

        finite(Float(text))
      end

      def self.decimal(value)
        return nil if parse(value).nil?

        BigDecimal(value.is_a?(::Numeric) ? value.to_s : clean(value))
      end

      def self.clean(value)
        value.to_s.gsub(STRIPPED, "").sub(CURRENCY) { ::Regexp.last_match(1) }
      end

      def self.finite(number)
        number.finite? ? number : nil
      end

      def self.format(number)
        return number.to_i.to_s if number == number.to_i

        number.to_s
      end

      def self.preview(value)
        value.inspect.truncate(PREVIEW_LENGTH)
      end
    end
  end
end
