require "rails_helper"

RSpec.describe CompletionKit::Metric, type: :model do
  it "fills in default rubric bands on a new metric" do
    metric = described_class.create!(name: "Default metric")

    expect(metric.criteria).to be_nil
    expect(metric.evaluation_steps).to eq([])
    expect(metric.rubric_bands.length).to eq(5)
    expect(metric.rubric_bands.first).to include("stars" => 5)
    expect(metric.rubric_bands.last).to include("stars" => 1)
  end

  it "generates rubric text from star bands" do
    metric = described_class.create!(name: "Test metric")

    expect(metric.display_rubric_text).to include("5 stars:")
    expect(metric.display_rubric_text).to include("1 star:")
  end

  it "normalizes rubric bands preserving only valid star entries" do
    metric = build(
      :completion_kit_metric,
      rubric_bands: [
        "junk",
        { stars: 99, description: "Ignore" },
        { stars: 5, description: "Great" },
        { stars: 3, description: "OK" }
      ]
    )

    metric.valid?

    expect(metric.rubric_bands.length).to eq(5)
    expect(metric.rubric_bands.find { |b| b["stars"] == 5 }["description"]).to eq("Great")
    expect(metric.rubric_bands.find { |b| b["stars"] == 3 }["description"]).to eq("OK")
  end

  it "generates a unique key from name" do
    metric = described_class.create!(name: "Hallucination Detection")

    expect(metric.key).to eq("hallucination-detection")
  end
end
