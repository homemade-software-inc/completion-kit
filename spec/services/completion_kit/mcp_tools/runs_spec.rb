require "rails_helper"

RSpec.describe CompletionKit::McpTools::Runs do
  describe ".definitions" do
    it "returns 7 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(7)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        runs_list runs_get runs_create runs_update
        runs_delete runs_generate runs_judge
      ])
    end
  end

  describe ".call" do
    let!(:prompt) { create(:completion_kit_prompt) }
    let!(:run) { create(:completion_kit_run, prompt: prompt, name: "Test Run") }

    it "lists runs" do
      result = described_class.call("runs_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content).to be_an(Array)
      expect(content.first["name"]).to eq("Test Run")
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
      result = described_class.call("runs_generate", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end

    it "returns error on invalid create" do
      result = described_class.call("runs_create", {"name" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("runs_update", {"id" => run.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "enqueues judge" do
      result = described_class.call("runs_judge", {"id" => run.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(run.id)
    end
  end
end
