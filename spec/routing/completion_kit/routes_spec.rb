require "rails_helper"

RSpec.describe CompletionKit::Engine.routes, type: :routing do
  it "routes nested responses to the responses controller" do
    route = described_class.recognize_path("/runs/12/responses/34", method: :get)

    expect(route).to include(
      controller: "completion_kit/responses",
      action: "show",
      run_id: "12",
      id: "34"
    )
  end

  it "routes datasets" do
    expect(described_class.recognize_path("/datasets", method: :get)).to include(
      controller: "completion_kit/datasets",
      action: "index"
    )
  end

  it "routes criteria and metrics" do
    expect(described_class.recognize_path("/criteria/12", method: :get)).to include(
      controller: "completion_kit/criteria",
      action: "show",
      id: "12"
    )
    expect(described_class.recognize_path("/metrics/7", method: :get)).to include(
      controller: "completion_kit/metrics",
      action: "show",
      id: "7"
    )
  end
end
