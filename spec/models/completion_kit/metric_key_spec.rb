require "rails_helper"

RSpec.describe CompletionKit::Metric, "key generation" do
  it "auto-generates key from name" do
    metric = create(:completion_kit_metric, name: "Relevance & Completeness")
    expect(metric.key).to eq("relevance-completeness")
  end

  it "does not overwrite an existing key" do
    metric = create(:completion_kit_metric, name: "Relevance", key: "custom_key")
    expect(metric.key).to eq("custom_key")
  end

  it "enforces uniqueness on key" do
    create(:completion_kit_metric, name: "Relevance", key: "relevance")
    duplicate = build(:completion_kit_metric, name: "Other", key: "relevance")
    expect(duplicate).not_to be_valid
  end
end
