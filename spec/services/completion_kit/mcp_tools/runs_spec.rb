require "rails_helper"

RSpec.describe CompletionKit::McpTools::Runs do
  describe ".definitions" do
    it "returns 6 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(6)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        runs_list runs_get runs_create runs_update
        runs_delete runs_generate
      ])
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
  end
end
