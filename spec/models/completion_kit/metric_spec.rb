require "rails_helper"

RSpec.describe CompletionKit::Metric, type: :model do
  describe "destroy cascade" do
    it "destroys metric_group memberships and nullifies the metric link on reviews" do
      metric = create(:completion_kit_metric)
      group = create(:completion_kit_metric_group)
      create(:completion_kit_metric_group_membership, metric_group: group, metric: metric)
      response = create(:completion_kit_response, run: create(:completion_kit_run, prompt: create(:completion_kit_prompt, template: "Static prompt without variables")))
      review = create(:completion_kit_review, response: response, metric: metric)

      expect { metric.destroy! }
        .to change(CompletionKit::MetricGroupMembership, :count).by(-1)
        .and change(CompletionKit::Review, :count).by(0)

      expect(review.reload.metric_id).to be_nil
    end
  end

  it "fills in default rubric bands on a new metric" do
    metric = described_class.create!(name: "Default metric")

    expect(metric.instruction).to be_nil
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

  it "normalizes rubric bands from indexed hash params (form submission)" do
    metric = build(
      :completion_kit_metric,
      rubric_bands: {"0" => {"stars" => "5", "description" => "Great"}, "1" => {"stars" => "3", "description" => "OK"}}
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
