require "rails_helper"

RSpec.describe CompletionKit::McpTools::Judges do
  let(:metric) { create(:completion_kit_metric) }
  let(:dataset) do
    create(:completion_kit_dataset, csv_data: "input,actual_output,predicted\nQ?,A,A'\n")
  end

  describe "judges_replay" do
    it "creates a judge-only run with the supplied metric, dataset, and judge model" do
      result = described_class.call("judges_replay", {
        "name" => "replay v1", "metric_id" => metric.id, "dataset_id" => dataset.id,
        "judge_model" => "claude-3-7-sonnet-latest"
      })
      text = result[:content].first[:text]
      expect(text).to include("replay v1")
      expect(text).to include("claude-3-7-sonnet-latest")
      run = CompletionKit::Run.last
      expect(run.judge_model).to eq("claude-3-7-sonnet-latest")
      expect(run.output_column).to eq("actual_output")
      expect(run.metrics).to include(metric)
    end

    it "honors an explicit output_column" do
      described_class.call("judges_replay", {
        "name" => "replay r", "metric_id" => metric.id, "dataset_id" => dataset.id,
        "judge_model" => "claude-3-7-sonnet-latest", "output_column" => "predicted"
      })
      expect(CompletionKit::Run.last.output_column).to eq("predicted")
    end

    it "returns isError when the run fails to save" do
      allow_any_instance_of(CompletionKit::Run).to receive(:save).and_return(false)
      allow_any_instance_of(CompletionKit::Run).to receive_message_chain(:errors, :full_messages).and_return(["bad"])
      result = described_class.call("judges_replay", {
        "name" => "replay", "metric_id" => metric.id, "dataset_id" => dataset.id,
        "judge_model" => "claude-3-7-sonnet-latest"
      })
      expect(result[:isError]).to be(true)
    end
  end

  describe "judges_compare" do
    let(:run) { create(:completion_kit_run) }
    let(:published_version) { CompletionKit::MetricVersion.ensure_current_for(metric) }
    let(:draft_version) do
      CompletionKit::MetricVersion.create!(metric: metric, instruction: "fresh", current: false, state: "draft", source: "edit")
    end

    def add_agreement(version, verdict:, response: nil, corrected: nil, created_by: SecureRandom.uuid)
      response ||= create(:completion_kit_response, run: run)
      create(:completion_kit_agreement,
             run: run, response: response, metric: metric,
             metric_version: version, verdict: verdict,
             corrected_score: corrected, created_by: created_by)
    end

    it "returns side-by-side stats and a recommendation when both versions clear the data gate" do
      20.times { add_agreement(published_version, verdict: "agree") }
      18.times { add_agreement(draft_version, verdict: "agree") }
      2.times  { add_agreement(draft_version, verdict: "disagree", corrected: 3) }

      result = described_class.call("judges_compare", {
        "metric_id" => metric.id,
        "metric_version_a_id" => published_version.id,
        "metric_version_b_id" => draft_version.id
      })
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["a"]["sample_size"]).to eq(20)
      expect(payload["b"]["sample_size"]).to eq(20)
      expect(payload["delta"]["agreement"]["delta"]).to be < 0
      expect(payload["recommendation"]["state"]).to eq("hold")
    end

    it "flags need_more_data when combined sample is under 30" do
      5.times { add_agreement(published_version, verdict: "agree") }
      result = described_class.call("judges_compare", {
        "metric_id" => metric.id,
        "metric_version_a_id" => published_version.id,
        "metric_version_b_id" => draft_version.id
      })
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["recommendation"]["state"]).to eq("need_more_data")
    end

    it "returns recommend when B's agreement is materially higher than A's" do
      20.times { add_agreement(published_version, verdict: "agree") }
      4.times { add_agreement(published_version, verdict: "disagree", corrected: 3) }
      20.times { add_agreement(draft_version, verdict: "agree") }
      result = described_class.call("judges_compare", {
        "metric_id" => metric.id,
        "metric_version_a_id" => published_version.id,
        "metric_version_b_id" => draft_version.id
      })
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["recommendation"]["state"]).to eq("recommend")
    end

    it "returns no_change when the lift sits inside the noise band" do
      20.times { add_agreement(published_version, verdict: "agree") }
      20.times { add_agreement(draft_version, verdict: "agree") }
      result = described_class.call("judges_compare", {
        "metric_id" => metric.id,
        "metric_version_a_id" => published_version.id,
        "metric_version_b_id" => draft_version.id
      })
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["recommendation"]["state"]).to eq("no_change")
    end

    it "returns no_change when one version has no verdicts even after clearing the combined gate" do
      30.times { add_agreement(published_version, verdict: "agree") }
      result = described_class.call("judges_compare", {
        "metric_id" => metric.id,
        "metric_version_a_id" => published_version.id,
        "metric_version_b_id" => draft_version.id
      })
      payload = JSON.parse(result[:content].first[:text])
      expect(payload["recommendation"]["state"]).to eq("no_change")
      expect(payload["recommendation"]["reason"]).to include("Not enough verdicts")
    end
  end

  it "exposes the judges tool definitions" do
    names = described_class.definitions.map { |t| t[:name] }
    expect(names).to match_array(%w[judges_replay judges_compare])
  end
end
