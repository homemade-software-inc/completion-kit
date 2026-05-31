require "rails_helper"

RSpec.describe CompletionKit::McpTools::Agreements do
  let(:metric) { create(:completion_kit_metric) }
  let(:run) { create(:completion_kit_run) }
  let(:response_row) { create(:completion_kit_response, run: run) }

  describe "agreements_create" do
    it "creates a new agreement and returns its payload" do
      result = described_class.call("agreements_create", {
        "run_id" => run.id, "response_id" => response_row.id, "metric_id" => metric.id,
        "verdict" => "agree", "created_by" => "alice"
      })
      expect(result[:content].first[:text]).to include("agree", "alice")
      expect(CompletionKit::Agreement.count).to eq(1)
    end

    it "upserts on a repeat call with the same identity triple" do
      described_class.call("agreements_create", {
        "run_id" => run.id, "response_id" => response_row.id, "metric_id" => metric.id,
        "verdict" => "agree", "created_by" => "alice"
      })
      described_class.call("agreements_create", {
        "run_id" => run.id, "response_id" => response_row.id, "metric_id" => metric.id,
        "verdict" => "disagree", "corrected_score" => 3.0, "note" => "off by a star",
        "created_by" => "alice"
      })
      expect(CompletionKit::Agreement.count).to eq(1)
      expect(CompletionKit::Agreement.first.verdict).to eq("disagree")
    end

    it "defaults created_by to 'mcp'" do
      described_class.call("agreements_create", {
        "run_id" => run.id, "response_id" => response_row.id, "metric_id" => metric.id,
        "verdict" => "borderline"
      })
      expect(CompletionKit::Agreement.first.created_by).to eq("mcp")
    end

    it "returns isError on validation failure" do
      result = described_class.call("agreements_create", {
        "run_id" => run.id, "response_id" => response_row.id, "metric_id" => metric.id,
        "verdict" => "disagree", "created_by" => "alice"
      })
      expect(result[:isError]).to be(true)
    end
  end

  describe "agreements_list" do
    it "filters by run_id, response_id, metric_id, and created_by" do
      other_response = create(:completion_kit_response, run: run)
      jv = CompletionKit::MetricVersion.ensure_current_for(metric)
      create(:completion_kit_agreement,
             run: run, response: response_row, metric: metric, metric_version: jv,
             created_by: "alice", verdict: "agree")
      create(:completion_kit_agreement,
             run: run, response: other_response, metric: metric, metric_version: jv,
             created_by: "alice", verdict: "disagree", corrected_score: 2.0)
      create(:completion_kit_agreement,
             run: run, response: response_row, metric: metric, metric_version: jv,
             created_by: "bob", verdict: "borderline")

      filtered = described_class.call("agreements_list", {
        "run_id" => run.id, "response_id" => response_row.id, "created_by" => "alice"
      })
      expect(filtered[:content].first[:text]).to include("agree")
      expect(filtered[:content].first[:text]).not_to include("disagree")

      by_metric = described_class.call("agreements_list", { "metric_id" => metric.id })
      expect(by_metric[:content].first[:text].scan("verdict").size).to eq(3)
    end
  end

  it "exposes tool definitions" do
    names = described_class.definitions.map { |t| t[:name] }
    expect(names).to match_array(%w[agreements_list agreements_create])
  end
end
