require "rails_helper"

RSpec.describe CompletionKit::Checks::NumericValue do
  describe ".parse" do
    it "passes a number through as a float" do
      expect(described_class.parse(5)).to eq(5.0)
      expect(described_class.parse(1.5)).to eq(1.5)
    end

    it "reads a plain numeric string" do
      expect(described_class.parse("82000")).to eq(82_000.0)
      expect(described_class.parse("0.82")).to eq(0.82)
      expect(described_class.parse("-3")).to eq(-3.0)
    end

    it "ignores the punctuation a figure is written with" do
      expect(described_class.parse("82,000")).to eq(82_000.0)
      expect(described_class.parse(" 82 000 ")).to eq(82_000.0)
      expect(described_class.parse("82_000")).to eq(82_000.0)
    end

    it "reads a comma as a thousands separator only when three digits follow every comma" do
      expect(described_class.parse("1,000")).to eq(1_000.0)
      expect(described_class.parse("1,000,000")).to eq(1_000_000.0)
      expect(described_class.parse("82,000.50")).to eq(82_000.5)
      expect(described_class.parse("-$1,000")).to eq(-1_000.0)
    end

    it "refuses a decimal comma rather than reading it as a thousands separator" do
      expect(described_class.parse("1,5")).to be_nil
      expect(described_class.parse("1.234,56")).to be_nil
      expect(described_class.parse("€1.234,56")).to be_nil
      expect(described_class.parse("82 000,50")).to be_nil
    end

    it "refuses commas that do not group thousands" do
      expect(described_class.parse("1,0000")).to be_nil
      expect(described_class.parse("1234,567")).to be_nil
      expect(described_class.parse(",000")).to be_nil
      expect(described_class.parse("1,000.000,5")).to be_nil
    end

    it "ignores the non-breaking and thin spaces some locales group thousands with" do
      expect(described_class.parse("82\u00A0000")).to eq(82_000.0)
      expect(described_class.parse("82\u2009000")).to eq(82_000.0)
      expect(described_class.parse("1\u202F234\u202F567")).to eq(1_234_567.0)
    end

    it "reads a leading currency symbol off a sticker price" do
      expect(described_class.parse("$24,995")).to eq(24_995.0)
      expect(described_class.parse("£10")).to eq(10.0)
      expect(described_class.parse("€10")).to eq(10.0)
    end

    it "returns nil for anything that is not a number, rather than zero" do
      expect(described_class.parse("unknown")).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse("   ")).to be_nil
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("-")).to be_nil
    end

    it "reads a currency symbol that sits inside the sign either way round" do
      expect(described_class.parse("-$5")).to eq(-5.0)
      expect(described_class.parse("$-5")).to eq(-5.0)
    end

    it "refuses a hexadecimal literal, which Float would otherwise accept" do
      expect(described_class.parse("0x10")).to be_nil
    end

    it "refuses a value that is not finite rather than letting it reach the formatter" do
      expect(described_class.parse("1e400")).to be_nil
      expect(described_class.parse("Infinity")).to be_nil
      expect(described_class.parse("NaN")).to be_nil
      expect(described_class.parse(Float::INFINITY)).to be_nil
      expect(described_class.parse(Float::NAN)).to be_nil
    end

    it "still reads a legitimate exponent" do
      expect(described_class.parse("1e3")).to eq(1000.0)
    end
  end

  describe ".decimal" do
    it "reads a figure as an exact decimal" do
      expect(described_class.decimal("$0.30")).to eq(BigDecimal("0.3"))
      expect(described_class.decimal("82,000")).to eq(BigDecimal("82000"))
    end

    it "reads a float through its shortest written form rather than its binary value" do
      expect(described_class.decimal(0.1)).to eq(BigDecimal("0.1"))
      expect(described_class.decimal(7)).to eq(BigDecimal("7"))
    end

    it "returns nil for anything parse would refuse" do
      expect(described_class.decimal("1,5")).to be_nil
      expect(described_class.decimal("unknown")).to be_nil
      expect(described_class.decimal("1e400")).to be_nil
      expect(described_class.decimal(nil)).to be_nil
    end
  end

  describe ".preview" do
    it "shows a short value whole and cuts a long one short" do
      expect(described_class.preview("n/a")).to eq("\"n/a\"")
      expect(described_class.preview("x" * 200)).to eq("#{"\"" + "x" * 36}...")
      expect(described_class.preview(nil)).to eq("nil")
    end
  end

  describe ".format" do
    it "drops the decimal point from a whole number" do
      expect(described_class.format(3.0)).to eq("3")
      expect(described_class.format(-40.0)).to eq("-40")
    end

    it "keeps a fractional part" do
      expect(described_class.format(0.8)).to eq("0.8")
    end

    it "writes a decimal in plain notation" do
      expect(described_class.format(BigDecimal("1.999"))).to eq("1.999")
      expect(described_class.format(BigDecimal("20.00"))).to eq("20")
    end
  end
end
