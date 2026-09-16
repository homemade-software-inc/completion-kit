require "rails_helper"
require "socket"
require "faraday"

RSpec.describe CompletionKit::ProviderEndpoint do
  around do |example|
    original = CompletionKit.config.allow_loopback_endpoints
    example.run
    CompletionKit.config.allow_loopback_endpoints = original
  end

  describe ".validate" do
    it "is empty for a literal public IP" do
      expect(described_class.validate("http://8.8.8.8/")).to eq([])
    end

    it "is empty for a resolvable public hostname" do
      allow(described_class).to receive(:resolve).with("api.example").and_return(["93.184.216.34"])
      expect(described_class.validate("http://api.example/v1")).to eq([])
    end

    it "returns :invalid_url for a bad URL" do
      expect(described_class.validate("ftp://example.com")).to eq([:invalid_url])
      expect(described_class.validate("http://")).to eq([:invalid_url])
      expect(described_class.validate("http://e xample.com")).to eq([:invalid_url])
    end

    it "returns :unresolvable when DNS yields nothing" do
      allow(described_class).to receive(:resolve).with("nowhere.example").and_return([])
      expect(described_class.validate("http://nowhere.example")).to eq([:unresolvable])
    end

    it "returns :unsafe_host for a private address" do
      expect(described_class.validate("http://10.0.0.5/")).to eq([:unsafe_host])
      expect(described_class.validate("http://192.168.1.10")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for a link-local address (cloud metadata)" do
      expect(described_class.validate("http://169.254.169.254/latest/meta-data")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for a link-local address written in hex" do
      expect(described_class.validate("http://0xA9FEA9FE/latest/meta-data")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for a link-local address written as one decimal number" do
      expect(described_class.validate("http://2852039166/")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for the shared address space used inside cloud networks" do
      expect(described_class.validate("http://100.64.0.1/")).to eq([:unsafe_host])
      expect(described_class.validate("http://[::ffff:100.64.0.1]/")).to eq([:unsafe_host])
    end

    it "returns :unresolvable when the resolver raises" do
      allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError, "getaddrinfo: nodename nor servname provided")
      expect(described_class.validate("http://nowhere.example")).to eq([:unresolvable])
    end

    it "returns :unsafe_host for the 0.0.0.0 unspecified address" do
      expect(described_class.validate("http://0.0.0.0/")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for non-zero addresses in 0.0.0.0/8" do
      expect(described_class.validate("http://0.1.2.3/")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for the IPv6 unspecified address" do
      expect(described_class.validate("http://[::]/")).to eq([:unsafe_host])
    end

    it "rejects loopback when allow_loopback_endpoints is false" do
      CompletionKit.config.allow_loopback_endpoints = false
      expect(described_class.validate("http://127.0.0.1:11434")).to eq([:unsafe_host])
      expect(described_class.validate("http://[::1]/")).to eq([:unsafe_host])
      expect(described_class.validate("http://127.0.0.1./")).to eq([:unsafe_host])
    end

    it "allows loopback when allow_loopback_endpoints is true" do
      CompletionKit.config.allow_loopback_endpoints = true
      expect(described_class.validate("http://127.0.0.1:11434")).to eq([])
    end
  end

  describe ".safe?" do
    it "is true for a valid resolvable public address" do
      expect(described_class.safe?("http://8.8.8.8/")).to eq(true)
    end

    it "is false for an unresolvable host, since the check cannot vouch for it" do
      allow(described_class).to receive(:resolve).with("nowhere.example").and_return([])
      expect(described_class.safe?("http://nowhere.example")).to eq(false)
    end

    it "is false for an invalid URL" do
      expect(described_class.safe?("not a url")).to eq(false)
    end

    it "is false for a private address" do
      expect(described_class.safe?("http://10.0.0.5/")).to eq(false)
    end

    it "is false for loopback when allow_loopback_endpoints is off" do
      CompletionKit.config.allow_loopback_endpoints = false
      expect(described_class.safe?("http://127.0.0.1:11434")).to eq(false)
    end
  end

  describe ".pinned_address" do
    it "returns the vetted address, preferring IPv4" do
      allow(described_class).to receive(:resolve).with("api.example").and_return(["2606:2800:220:1::1", "93.184.216.34"])
      expect(described_class.pinned_address("https://api.example/v1")).to eq("93.184.216.34")
    end

    it "falls back to an IPv6 address when there is no IPv4 one" do
      allow(described_class).to receive(:resolve).with("api.example").and_return(["2606:2800:220:1::1"])
      expect(described_class.pinned_address("https://api.example/v1")).to eq("2606:2800:220:1::1")
    end

    it "raises for a URL that is not http or https" do
      expect { described_class.pinned_address("ftp://example.com") }
        .to raise_error(described_class::UnsafeEndpoint, "is not a valid http or https URL")
    end

    it "raises for a host that cannot be resolved" do
      allow(described_class).to receive(:resolve).with("nowhere.example").and_return([])
      expect { described_class.pinned_address("http://nowhere.example") }
        .to raise_error(described_class::UnsafeEndpoint, "could not be resolved")
    end

    it "raises when any resolved address is internal" do
      allow(described_class).to receive(:resolve).with("mixed.example").and_return(["93.184.216.34", "10.0.0.5"])
      expect { described_class.pinned_address("http://mixed.example") }
        .to raise_error(described_class::UnsafeEndpoint, "resolves to a private address")
    end
  end

  describe ".pin" do
    it "connects to the vetted address instead of resolving the host again" do
      CompletionKit.config.allow_loopback_endpoints = true
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      received = Queue.new
      thread = Thread.new do
        client = server.accept
        lines = []
        while (line = client.gets) && line != "\r\n"
          lines << line
        end
        received << lines
        client.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        client.close
      end
      allow(described_class).to receive(:resolve).with("pinned.example").and_return(["127.0.0.1"])
      url = "http://pinned.example:#{port}"

      response = Faraday.new(url: url) { |f| described_class.pin(f, url) }.get("/v1/models")

      expect(response.body).to eq("ok")
      expect(received.pop).to include("Host: pinned.example:#{port}\r\n")
      expect(described_class).to have_received(:resolve).once
    ensure
      thread&.join(1)
      server&.close
    end

    it "raises before any connection is built for an internal address" do
      builder = double("Faraday::RackBuilder")
      allow(builder).to receive(:adapter)

      expect { described_class.pin(builder, "http://0xA9FEA9FE/") }
        .to raise_error(described_class::UnsafeEndpoint, "resolves to a private address")
      expect(builder).not_to have_received(:adapter)
    end
  end
end
