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

  describe ".format" do
    it "drops the decimal point from a whole number" do
      expect(described_class.format(3.0)).to eq("3")
      expect(described_class.format(-40.0)).to eq("-40")
    end

    it "keeps a fractional part" do
      expect(described_class.format(0.8)).to eq("0.8")
    end
  end
end
