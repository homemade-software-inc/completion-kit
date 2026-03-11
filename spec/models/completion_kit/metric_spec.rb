require "rails_helper"

RSpec.describe CompletionKit::Metric, type: :model do
  it "fills in default guidance and rubric text" do
    metric = described_class.create!(name: "Default metric")

    expect(metric.guidance_text).to eq("")
    expect(metric.rubric_text).to eq(described_class.default_rubric_text)
    expect(metric.rubric_bands_for_form.first["range"]).to eq("1-2")
  end

  it "normalizes rubric bands and ignores invalid entries" do
    metric = build(
      :completion_kit_metric,
      rubric_text: nil,
      rubric_bands: [
        "junk",
        { range: "12-13", criteria: "Ignore" },
        { range: "9-10", criteria: "Great" }
      ]
    )

    metric.valid?

    expect(metric.rubric_bands.last).to include("range" => "9-10", "criteria" => "Great")
    expect(metric.display_rubric_text).to include("Great")
  end

  it "parses structured rubric text and handles blank text" do
    metric = build(:completion_kit_metric, rubric_bands: nil, rubric_text: <<~RUBRIC)
      unknown
      Criteria: Ignore me

      9-10
      Criteria: Keep me
    RUBRIC

    expect(metric.rubric_bands_for_form.last).to include("range" => "9-10", "criteria" => "Keep me")
    expect(metric.send(:parsed_rubric_bands_from_text, "")).to eq([])
    expect(metric.send(:parsed_rubric_bands_from_text, "   \n\n \n\n")).to eq([])
  end

  it "keeps explicit rubric text when rubric bands are absent" do
    metric = create(:completion_kit_metric, rubric_bands: nil, rubric_text: "Explicit rubric")

    expect(metric.rubric_text).to eq("Explicit rubric")
  end
end
