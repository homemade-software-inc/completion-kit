require "rails_helper"

RSpec.describe CompletionKit::Tag, type: :model do
  describe "validations" do
    it "requires a name" do
      tag = described_class.new(name: "")
      expect(tag).not_to be_valid
      expect(tag.errors[:name]).to include("can't be blank")
    end

    it "rejects names longer than 64 characters" do
      tag = described_class.new(name: "a" * 65)
      expect(tag).not_to be_valid
      expect(tag.errors[:name]).to be_present
    end

    it "rejects names with disallowed characters" do
      tag = described_class.new(name: "marine/biology")
      expect(tag).not_to be_valid
      expect(tag.errors[:name]).to be_present
    end

    it "accepts letters, digits, spaces, hyphens, underscores" do
      tag = described_class.new(name: "marine biology-2_research")
      expect(tag).to be_valid
    end

    it "is unique by name (case-insensitive via normalization)" do
      described_class.create!(name: "Marine Biology")
      dup = described_class.new(name: "marine biology")
      expect(dup).not_to be_valid
    end
  end

  describe "normalization" do
    it "stores names lowercased and stripped" do
      tag = described_class.create!(name: "  Marine Biology  ")
      expect(tag.reload.name).to eq("marine biology")
    end
  end

  describe "color autoassignment" do
    it "assigns the first palette color to the first tag" do
      tag = described_class.create!(name: "first")
      expect(tag.color).to eq("crimson")
    end

    it "round-robins through the 10-color palette" do
      colors = 12.times.map { |i| described_class.create!(name: "tag #{i}").color }
      expect(colors).to eq(
        described_class::COLORS + described_class::COLORS.first(2)
      )
    end

    it "does not overwrite an explicitly set color" do
      tag = described_class.create!(name: "manual", color: "amethyst")
      expect(tag.color).to eq("amethyst")
    end

    it "rejects unknown colors" do
      tag = described_class.new(name: "x", color: "magenta")
      expect(tag).not_to be_valid
      expect(tag.errors[:color]).to be_present
    end
  end

  describe "associations" do
    it "destroys taggings when the tag is destroyed" do
      pending "Tagging model created in Task 3"
      raise "unimplemented"
    end
  end

  describe "#as_json" do
    it "exposes id, name, color, timestamps" do
      tag = described_class.create!(name: "x")
      expect(tag.as_json.keys).to match_array(%i[id name color created_at updated_at])
    end
  end
end
