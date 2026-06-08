require "rails_helper"

RSpec.describe CompletionKit::McpTools::Datasets do
  describe ".definitions" do
    it "returns 6 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(6)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        datasets_list datasets_get datasets_create datasets_update datasets_delete datasets_create_from_url
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

  describe "datasets_create_from_url" do
    def stub_fetch(body: "", success: true, status: 200, raises: nil)
      options = Struct.new(:timeout, :open_timeout).new
      conn = instance_double("Faraday::Connection")
      allow(conn).to receive(:options).and_return(options)
      allow(conn).to receive(:adapter)
      allow(Faraday).to receive(:new).and_yield(conn).and_return(conn)
      if raises
        allow(conn).to receive(:get).and_raise(raises)
      else
        allow(conn).to receive(:get).and_return(
          instance_double("Faraday::Response", success?: success, body: body, status: status)
        )
      end
    end

    it "downloads the CSV and creates a dataset, with tags" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([])
      stub_fetch(body: "content,expected_output\nhi,hello\n")

      result = described_class.call("datasets_create_from_url",
        {"name" => "Remote DS", "url" => "https://example.com/data.csv", "tag_names" => ["remote"]})

      content = JSON.parse(result[:content].first[:text])
      expect(content["name"]).to eq("Remote DS")
      ds = CompletionKit::Dataset.find(content["id"])
      expect(ds.csv_data).to include("content,expected_output")
      expect(ds.tag_names).to eq(["remote"])
    end

    it "rejects an SSRF-unsafe url without fetching" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([:unsafe_host])

      expect do
        @result = described_class.call("datasets_create_from_url",
          {"name" => "x", "url" => "http://169.254.169.254/latest/meta-data"})
      end.not_to change(CompletionKit::Dataset, :count)
      expect(@result[:isError]).to be(true)
    end

    it "returns isError when the download fails" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([])
      stub_fetch(success: false, status: 404)

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/missing.csv"})
      expect(result[:isError]).to be(true)
    end

    it "rejects a CSV larger than the size limit" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([])
      stub_fetch(body: "a" * (described_class::MAX_CSV_BYTES + 1))

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/huge.csv"})
      expect(result[:isError]).to be(true)
    end

    it "returns isError when the dataset fails to save" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([])
      stub_fetch(body: "col\nval")

      result = described_class.call("datasets_create_from_url",
        {"name" => "", "url" => "https://example.com/data.csv"})
      expect(result[:isError]).to be(true)
    end

    it "returns isError when the fetch raises a Faraday error" do
      allow(CompletionKit::ProviderEndpoint).to receive(:validate).and_return([])
      stub_fetch(raises: Faraday::ConnectionFailed.new("boom"))

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/data.csv"})
      expect(result[:isError]).to be(true)
    end
  end
end
