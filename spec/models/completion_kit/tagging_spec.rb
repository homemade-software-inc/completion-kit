require "rails_helper"

RSpec.describe CompletionKit::Tagging, type: :model do
  let(:tag) { create(:completion_kit_tag) }
  let(:metric) { create(:completion_kit_metric) }

  it "requires a tag" do
    tagging = described_class.new(taggable: metric)
    expect(tagging).not_to be_valid
  end

  it "requires a taggable" do
    tagging = described_class.new(tag: tag)
    expect(tagging).not_to be_valid
  end

  it "is valid with both" do
    expect(described_class.new(tag: tag, taggable: metric)).to be_valid
  end

  it "is unique per (tag_id, taggable_type, taggable_id)" do
    described_class.create!(tag: tag, taggable: metric)
    dup = described_class.new(tag: tag, taggable: metric)
    expect(dup).not_to be_valid
  end

  it "allows the same tag on different taggable types" do
    other_metric = create(:completion_kit_metric)
    described_class.create!(tag: tag, taggable: metric)
    expect(described_class.new(tag: tag, taggable: other_metric)).to be_valid
  end
end
