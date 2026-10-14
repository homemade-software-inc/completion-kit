require "rails_helper"
require "socket"

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
    before do
      allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"])
    end

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
      stub_fetch(body: "secret")

      expect do
        @result = described_class.call("datasets_create_from_url",
          {"name" => "x", "url" => "http://169.254.169.254/latest/meta-data"})
      end.not_to change(CompletionKit::Dataset, :count)
      expect(@result[:isError]).to be(true)
      expect(@result[:content].first[:text]).to eq("URL is not allowed: it does not resolve to a public address.")
    end

    it "rejects a url whose host cannot be resolved" do
      allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return([])

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://gone.example.test/data.csv"})
      expect(result[:isError]).to be(true)
      expect(result[:content].first[:text]).to eq("URL is not allowed: it does not resolve to a public address.")
    end

    it "gives a name that does not resolve and a name that resolves privately the same outcome" do
      allow(CompletionKit::ProviderEndpoint).to receive(:resolve).with("gone.example.test").and_return([])
      allow(CompletionKit::ProviderEndpoint).to receive(:resolve).with("internal.example.test").and_return(["10.0.0.5"])

      results = %w[gone.example.test internal.example.test].map do |host|
        described_class.call("datasets_create_from_url", {"name" => "x", "url" => "https://#{host}/data.csv"})
      end
      expect(results.uniq.length).to eq(1)
      expect(results.first[:isError]).to be(true)
    end

    it "pins the download to the checked address" do
      stub_fetch(body: "content\nhi\n")
      allow(CompletionKit::ProviderEndpoint).to receive(:pin).and_call_original

      described_class.call("datasets_create_from_url",
        {"name" => "Pinned", "url" => "https://example.com/data.csv"})
      expect(CompletionKit::ProviderEndpoint).to have_received(:pin).with(anything, "https://example.com/data.csv")
    end

    it "returns isError when the download fails" do
      stub_fetch(success: false, status: 404)

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/missing.csv"})
      expect(result[:isError]).to be(true)
    end

    it "rejects a CSV larger than the size limit" do
      stub_fetch(body: "a" * (described_class::MAX_CSV_BYTES + 1))

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/huge.csv"})
      expect(result[:isError]).to be(true)
    end

    it "returns isError when the dataset fails to save" do
      stub_fetch(body: "col\nval")

      result = described_class.call("datasets_create_from_url",
        {"name" => "", "url" => "https://example.com/data.csv"})
      expect(result[:isError]).to be(true)
    end

    it "returns isError when the fetch raises a Faraday error" do
      stub_fetch(raises: Faraday::ConnectionFailed.new("boom"))

      result = described_class.call("datasets_create_from_url",
        {"name" => "x", "url" => "https://example.com/data.csv"})
      expect(result[:isError]).to be(true)
    end

    it "answers every transport failure with a fixed message and logs the detail" do
      allow(Rails.logger).to receive(:warn)
      texts = TransportErrors.samples.values.map do |error, _message|
        stub_fetch(raises: error)
        described_class.call("datasets_create_from_url",
          {"name" => "x", "url" => "https://example.com/data.csv"})[:content].first[:text]
      end

      expect(texts).to eq(TransportErrors.samples.values.map { |_error, message| "Could not download CSV. #{message}" })
      expect(texts.none? { |text| TransportErrors.leaks?(text) }).to be(true)
      expect(Rails.logger).to have_received(:warn).with(/Connection refused/)
      expect(Rails.logger).to have_received(:warn).with(/ReadTimeout/)
    end

    context "against real sockets" do
      around do |example|
        original = CompletionKit.config.allow_loopback_endpoints
        CompletionKit.config.allow_loopback_endpoints = true
        example.run
        CompletionKit.config.allow_loopback_endpoints = original
      end

      before { allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_call_original }

      def fetch_text(port)
        described_class.call("datasets_create_from_url",
          {"name" => "x", "url" => "http://localhost:#{port}/data.csv"})[:content].first[:text]
      end

      it "hides a closed port and a service that is not HTTP behind the same message" do
        closed = TCPServer.new("127.0.0.1", 0)
        closed_port = closed.addr[1]
        closed.close

        server = TCPServer.new("127.0.0.1", 0)
        thread = Thread.new do
          client = server.accept
          client.write("SSH-2.0-OpenSSH_9.6 test\r\n")
          client.close
        end

        texts = [fetch_text(closed_port), fetch_text(server.addr[1])]

        expect(texts.uniq).to eq(["Could not download CSV. Could not connect to the endpoint."])
        expect(texts.none? { |text| TransportErrors.leaks?(text) || text.include?("127.0.0.1") }).to be(true)
      ensure
        thread&.join(1)
        server&.close
      end
    end
  end
end
