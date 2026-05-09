require "rails_helper"

RSpec.describe CompletionKit::Taggable, type: :model do
  let(:metric) { create(:completion_kit_metric) }

  describe "#tag_names" do
    it "returns the names of associated tags" do
      tag = CompletionKit::Tag.create!(name: "marine biology")
      metric.tags << tag
      expect(metric.tag_names).to eq(["marine biology"])
    end
  end

  describe "#tag_names=" do
    it "creates tags that don't exist" do
      expect { metric.update!(tag_names: ["new tag"]) }.to change(CompletionKit::Tag, :count).by(1)
      expect(metric.tag_names).to eq(["new tag"])
    end

    it "reuses existing tags by name" do
      CompletionKit::Tag.create!(name: "existing")
      expect { metric.update!(tag_names: ["existing"]) }.not_to change(CompletionKit::Tag, :count)
      expect(metric.tag_names).to eq(["existing"])
    end

    it "normalizes case and whitespace" do
      metric.update!(tag_names: ["  Marine Biology  "])
      expect(metric.tag_names).to eq(["marine biology"])
    end

    it "deduplicates names" do
      metric.update!(tag_names: ["dup", "DUP", " dup "])
      expect(metric.tag_names).to eq(["dup"])
    end

    it "ignores blank names" do
      metric.update!(tag_names: ["real", "", nil, "  "])
      expect(metric.tag_names).to eq(["real"])
    end

    it "replaces the existing set on subsequent assignment" do
      metric.update!(tag_names: ["a", "b"])
      metric.update!(tag_names: ["c"])
      expect(metric.tag_names).to eq(["c"])
    end

    it "clears all tags when given an empty array" do
      metric.update!(tag_names: ["a", "b"])
      metric.update!(tag_names: [])
      expect(metric.tag_names).to eq([])
    end
  end

  describe "destroy cascade" do
    it "destroys taggings when the host record is destroyed" do
      metric.update!(tag_names: ["x"])
      expect { metric.destroy! }.to change(CompletionKit::Tagging, :count).by(-1)
    end
  end
end
