require "rails_helper"

RSpec.describe CompletionKit::McpTools::Runs do
  describe ".definitions" do
    it "returns 9 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(9)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        runs_list runs_get runs_create runs_update
        runs_delete runs_generate
        runs_regrade runs_rerun runs_retry_failures
      ])
    end

    it "advertises metric_group_id on the create and update schemas" do
      expect(described_class::TOOLS["runs_create"][:inputSchema][:properties]).to have_key(:metric_group_id)
      expect(described_class::TOOLS["runs_update"][:inputSchema][:properties]).to have_key(:metric_group_id)
    end

    it "advertises the generation parameters on the create and update schemas" do
      %w[runs_create runs_update].each do |tool|
        expect(described_class::TOOLS[tool][:inputSchema][:properties]).to include(:temperature, :max_tokens)
      end
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt, template: "Static prompt") }
    let!(:run) { create(:completion_kit_run, prompt: prompt, name: "Test Run") }

    before do
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_clear_responses)
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_replace_to)
      allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_append_to)
      allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
      allow(CompletionKit::JudgeReviewJob).to receive(:perform_later)
      allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
    end

    it "lists runs" do
      result = described_class.call("runs_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["name"]).to eq("Test Run")
    end

    it "lists only display-scoped runs" do
      create(:completion_kit_run, prompt: prompt, name: "Old MCP Run", created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      result = described_class.call("runs_list", {})
      names = JSON.parse(result[:content].first[:text]).map { |r| r["name"] }

      expect(names).to contain_exactly("Test Run")
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "gets a run by id" do
      result = described_class.call("runs_get", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "creates a run" do
      result = described_class.call("runs_create", {"name" => "New Run", "prompt_id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New Run")
    end

    it "creates a run with generation parameters" do
      result = described_class.call("runs_create", {
        "name" => "Long output", "prompt_id" => prompt.id, "temperature" => 0.2, "max_tokens" => 2048
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["temperature"]).to eq(0.2)
      expect(content["max_tokens"]).to eq(2048)
    end

    it "updates a run's generation parameters" do
      result = described_class.call("runs_update", {"id" => run.id, "temperature" => 0.0, "max_tokens" => 4096})
      content = JSON.parse(result[:content].first[:text])
      expect(content["temperature"]).to eq(0.0)
      expect(content["max_tokens"]).to eq(4096)
    end

    it "warns that a judge above temperature 0 makes scores irreproducible" do
      run.replace_metrics!([create(:completion_kit_metric).id])
      result = described_class.call("runs_update", {"id" => run.id, "judge_temperature" => 0.7})
      content = JSON.parse(result[:content].first[:text])
      expect(content["judge_temperature"]).to eq(0.7)
      expect(content["warning"]).to include("irreproducible")
    end

    it "omits the judge-temperature warning at the deterministic default" do
      run.replace_metrics!([create(:completion_kit_metric).id])
      result = described_class.call("runs_get", {"id" => run.id})
      expect(JSON.parse(result[:content].first[:text])).not_to have_key("warning")
    end

    it "rejects a judge_temperature outside 0 to 1" do
      result = described_class.call("runs_create", {"name" => "Bad judge", "prompt_id" => prompt.id, "judge_temperature" => 2})
      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to match(/Judge temperature/i)
    end

    it "rejects a non-positive max_tokens" do
      result = described_class.call("runs_create", {"name" => "Bad", "prompt_id" => prompt.id, "max_tokens" => 0})
      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to match(/Max tokens/i)
    end

    it "creates a run with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("runs_create", {"name" => "Run M", "prompt_id" => prompt.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "creates a judge-only run with no prompt_id and an output_column" do
      dataset = create(:completion_kit_dataset, csv_data: "input,actual_output\nhi,hello\n")

      result = described_class.call("runs_create", {
        "name" => "Judge baseline",
        "dataset_id" => dataset.id,
        "output_column" => "actual_output"
      })

      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Judge baseline")
      expect(content["prompt_id"]).to be_nil
      expect(content["output_column"]).to eq("actual_output")
    end

    it "creates a run with an expected_column answer-key override" do
      dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nphoto,WP0AA2A98KS103927\n")

      result = described_class.call("runs_create", {
        "name" => "Ground truth",
        "dataset_id" => dataset.id,
        "prompt_id" => prompt.id,
        "expected_column" => "true_vin"
      })

      content = JSON.parse(result[:content].first[:text])
      expect(content["expected_column"]).to eq("true_vin")
    end

    it "advertises expected_column on the create schema" do
      props = described_class::TOOLS["runs_create"][:inputSchema][:properties]
      expect(props).to have_key(:expected_column)
    end

    it "updates a run's expected_column" do
      dataset = create(:completion_kit_dataset, csv_data: "input,true_vin\nphoto,X1\n")
      run.update!(dataset: dataset)

      result = described_class.call("runs_update", {"id" => run.id, "expected_column" => "true_vin"})

      content = JSON.parse(result[:content].first[:text])
      expect(content["expected_column"]).to eq("true_vin")
    end

    it "updates a run" do
      result = described_class.call("runs_update", {"id" => run.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "updates a run with metric_ids" do
      metric = create(:completion_kit_metric)
      result = described_class.call("runs_update", {"id" => run.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])
      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "deletes a run" do
      result = described_class.call("runs_delete", {"id" => run.id})
      expect(result[:content].first[:text]).to include("deleted")
    end

    it "enqueues generate" do
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
      result = described_class.call("runs_generate", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "reports failure when generate cannot start" do
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
      allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Dataset has no rows")
      result = described_class.call("runs_generate", {"id" => run.id})
      expect(result[:content].first[:text]).to include("Dataset has no rows")
    end

    it "returns error on invalid create" do
      result = described_class.call("runs_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("runs_update", {"id" => run.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "round-trips tag_names on runs_create with auto-create" do
      expect do
        described_class.call("runs_create",
          {"name" => "Tagged Run", "prompt_id" => prompt.id, "tag_names" => ["new-tag"]})
      end.to change(CompletionKit::Tag, :count).by(1)
      found = CompletionKit::Run.find_by!(name: "Tagged Run")
      expect(found.tag_names).to eq(["new-tag"])
    end

    it "replaces tag_names on runs_update" do
      run.update!(tag_names: ["a", "b"])
      described_class.call("runs_update", {"id" => run.id, "tag_names" => ["c"]})
      expect(run.reload.tag_names).to eq(["c"])
    end

    it "expands metric_group_id to the group's metrics on runs_create" do
      metric = create(:completion_kit_metric)
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([metric.id])

      result = described_class.call("runs_create", {"name" => "Grouped", "prompt_id" => prompt.id, "metric_group_id" => group.id})
      content = JSON.parse(result[:content].first[:text])

      expect(content["metric_ids"]).to eq([metric.id])
    end

    it "expands metric_group_id to the group's metrics on runs_update" do
      metric = create(:completion_kit_metric)
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([metric.id])

      described_class.call("runs_update", {"id" => run.id, "metric_group_id" => group.id})

      expect(run.reload.metric_ids).to eq([metric.id])
    end

    it "prefers explicit metric_ids over metric_group_id when both are given" do
      chosen = create(:completion_kit_metric)
      group = create(:completion_kit_metric_group)
      group.replace_metrics!([create(:completion_kit_metric).id])

      result = described_class.call("runs_create", {"name" => "Both", "prompt_id" => prompt.id, "metric_ids" => [chosen.id], "metric_group_id" => group.id})
      content = JSON.parse(result[:content].first[:text])

      expect(content["metric_ids"]).to eq([chosen.id])
    end

    it "warns when a created run has no metrics attached, so the silent no-op is visible" do
      result = described_class.call("runs_create", {"name" => "Unjudged", "prompt_id" => prompt.id})
      content = JSON.parse(result[:content].first[:text])

      expect(content["metric_ids"]).to eq([])
      expect(content["warning"]).to include("No metrics are attached")
    end

    it "omits the warning once metrics are attached" do
      metric = create(:completion_kit_metric)
      result = described_class.call("runs_create", {"name" => "Judged", "prompt_id" => prompt.id, "metric_ids" => [metric.id]})
      content = JSON.parse(result[:content].first[:text])

      expect(content).not_to have_key("warning")
    end

    it "regrades a run's existing responses" do
      allow_any_instance_of(CompletionKit::Run).to receive(:regrade!).and_return(true)
      result = described_class.call("runs_regrade", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "reports an error when there is nothing to regrade" do
      allow_any_instance_of(CompletionKit::Run).to receive(:regrade!).and_return(false)
      result = described_class.call("runs_regrade", {"id" => run.id})
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("Nothing to re-grade")
    end

    it "reruns a run as a fresh started copy" do
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(true)
      expect do
        described_class.call("runs_rerun", {"id" => run.id})
      end.to change(CompletionKit::Run, :count).by(1)
    end

    it "reports an error when the rerun copy cannot start" do
      allow_any_instance_of(CompletionKit::Run).to receive(:start!).and_return(false)
      allow_any_instance_of(CompletionKit::Run).to receive(:failure_summary).and_return("Dataset has no rows")
      result = described_class.call("runs_rerun", {"id" => run.id})
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("Dataset has no rows")
    end

    it "retries only the failed responses of a run" do
      allow_any_instance_of(CompletionKit::Run).to receive(:stale_review_summary).and_return([])
      succeeded = create(:completion_kit_response, run: run, status: "succeeded")
      failed = create(:completion_kit_response, run: run, status: "failed")

      described_class.call("runs_retry_failures", {"id" => run.id})

      expect(failed.reload.status).to eq("pending")
      expect(succeeded.reload.status).to eq("succeeded")
      expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed.id)
    end

    it "limits a retry to specific response ids via only" do
      allow_any_instance_of(CompletionKit::Run).to receive(:stale_review_summary).and_return([])
      first = create(:completion_kit_response, run: run, status: "failed")
      second = create(:completion_kit_response, run: run, status: "failed")

      described_class.call("runs_retry_failures", {"id" => run.id, "only" => [first.id]})

      expect(first.reload.status).to eq("pending")
      expect(second.reload.status).to eq("failed")
    end

    it "refuses to retry failures when the judge version is stale" do
      allow_any_instance_of(CompletionKit::Run).to receive(:stale_review_summary).and_return([{metric: "x"}])
      result = described_class.call("runs_retry_failures", {"id" => run.id})
      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to include("Judge has changed")
    end
  end
end
