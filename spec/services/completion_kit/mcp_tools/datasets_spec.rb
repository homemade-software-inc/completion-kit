require "rails_helper"

RSpec.describe CompletionKit::McpTools::Datasets do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        datasets_list datasets_get datasets_create datasets_update datasets_delete
      ])
    end
  end

  describe ".call" do
    let!(:dataset) { create(:completion_kit_dataset, name: "Test DS") }

    it "lists datasets" do
      result = described_class.call("datasets_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["name"]).to eq("Test DS")
    end

    it "gets a dataset by id" do
      result = described_class.call("datasets_get", {"id" => dataset.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(dataset.id)
    end

    it "creates a dataset" do
      result = described_class.call("datasets_create", {"name" => "New", "csv_data" => "col1\nval1"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("New")
    end

    it "updates a dataset" do
      result = described_class.call("datasets_update", {"id" => dataset.id, "name" => "Updated"})
      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Updated")
    end

    it "returns error on invalid create" do
      result = described_class.call("datasets_create", {"name" => "", "csv_data" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("datasets_update", {"id" => dataset.id, "name" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a dataset" do
      result = described_class.call("datasets_delete", {"id" => dataset.id})
      expect(result[:content].first[:text]).to include("deleted")
    end

    it "round-trips tag_names on datasets_create with auto-create" do
      expect do
        described_class.call("datasets_create",
          {"name" => "Tagged DS", "csv_data" => "col\nval", "tag_names" => ["new-tag"]})
      end.to change(CompletionKit::Tag, :count).by(1)
      found = CompletionKit::Dataset.find_by!(name: "Tagged DS")
      expect(found.tag_names).to eq(["new-tag"])
    end

    it "replaces tag_names on datasets_update" do
      dataset.update!(tag_names: ["a", "b"])
      described_class.call("datasets_update", {"id" => dataset.id, "tag_names" => ["c"]})
      expect(dataset.reload.tag_names).to eq(["c"])
    end
  end
end
