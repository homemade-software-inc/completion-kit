require "rails_helper"

RSpec.describe CompletionKit::Engine.routes, type: :routing do
  it "routes nested test results to the test results controller" do
    route = described_class.recognize_path("/test_runs/12/test_results/34", method: :get)

    expect(route).to include(
      controller: "completion_kit/test_results",
      action: "show",
      test_run_id: "12",
      id: "34"
    )
  end

  it "routes metric groups and metrics" do
    expect(described_class.recognize_path("/metric_groups/12", method: :get)).to include(
      controller: "completion_kit/metric_groups",
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
