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

    it "adds a validation error instead of raising on a malformed name" do
      result = nil
      expect { result = metric.update(tag_names: ["c++"]) }.not_to raise_error
      expect(result).to be(false)
      expect(metric.errors[:base].join).to match(/not allowed/i)
      expect(CompletionKit::Tag.where(name: "c++")).not_to exist
    end

    it "reflects the assigned names before the record is saved" do
      metric.tag_names = ["pending-one", "pending-two"]
      expect(metric.tag_names).to eq(["pending-one", "pending-two"])
    end
  end

  describe "destroy cascade" do
    it "destroys taggings when the host record is destroyed" do
      metric.update!(tag_names: ["x"])
      expect { metric.destroy! }.to change(CompletionKit::Tagging, :count).by(-1)
    end
  end

  describe "host models" do
    it "is mixed into Metric, Prompt, Run, Dataset" do
      [CompletionKit::Metric, CompletionKit::Prompt,
       CompletionKit::Run, CompletionKit::Dataset].each do |klass|
        expect(klass.included_modules).to include(CompletionKit::Taggable)
      end
    end

    it "tag_names round-trips on Prompt" do
      prompt = create(:completion_kit_prompt)
      prompt.update!(tag_names: ["alpha"])
      expect(prompt.reload.tag_names).to eq(["alpha"])
    end

    it "tag_names round-trips on Run" do
      run = create(:completion_kit_run)
      run.update!(tag_names: ["beta"])
      expect(run.reload.tag_names).to eq(["beta"])
    end

    it "tag_names round-trips on Dataset" do
      dataset = create(:completion_kit_dataset)
      dataset.update!(tag_names: ["gamma"])
      expect(dataset.reload.tag_names).to eq(["gamma"])
    end
  end
end
