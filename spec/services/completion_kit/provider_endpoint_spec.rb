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

    [true, false].each do |loopback|
      context "with allow_loopback_endpoints #{loopback}" do
        before { CompletionKit.config.allow_loopback_endpoints = loopback }

        {
          "a NAT64 address of the metadata service" => "http://[64:ff9b::a9fe:a9fe]/",
          "a NAT64 address of a private host" => "http://[64:ff9b::a00:1]/",
          "a NAT64 address of loopback" => "http://[64:ff9b::7f00:1]/",
          "a local-use NAT64 address" => "http://[64:ff9b:1::a00:1]/",
          "a 6to4 address" => "http://[2002:a9fe:a9fe::]/",
          "a Teredo address" => "http://[2001:0:4136:e378:8000:63bf:5601:5601]/",
          "an IPv4-translated address" => "http://[::ffff:0:a9fe:a9fe]/",
          "an IETF protocol assignment address" => "http://192.0.0.192/",
          "a benchmarking address" => "http://198.18.0.1/",
          "a multicast address" => "http://224.0.0.1/",
          "a reserved address" => "http://240.0.0.1/",
          "the broadcast address" => "http://255.255.255.255/",
          "a documentation address" => "http://203.0.113.10/",
          "an IPv6 multicast address" => "http://[ff02::1]/",
          "an IPv6 site-local address" => "http://[fec0::1]/",
          "an IPv6 unique local address" => "http://[fc00::1]/",
          "an IPv6 link-local address" => "http://[fe80::1]/",
          "an IPv6 documentation address" => "http://[2001:db8::1]/",
          "an IPv6 discard address" => "http://[100::1]/"
        }.each do |label, url|
          it "returns :unsafe_host for #{label}" do
            expect(described_class.validate(url)).to eq([:unsafe_host])
          end
        end

        it "allows a public IPv6 address" do
          expect(described_class.validate("http://[2606:4700:4700::1111]/")).to eq([])
        end

        it "allows a NAT64 address of a public host" do
          expect(described_class.validate("http://[64:ff9b::808:808]/")).to eq([])
        end
      end
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
        .to raise_error(described_class::UnsafeEndpoint, "does not resolve to a public address")
    end

    it "raises when any resolved address is internal" do
      allow(described_class).to receive(:resolve).with("mixed.example").and_return(["93.184.216.34", "10.0.0.5"])
      expect { described_class.pinned_address("http://mixed.example") }
        .to raise_error(described_class::UnsafeEndpoint, "does not resolve to a public address")
    end

    it "gives a name that does not resolve and a name that resolves privately the same message" do
      allow(described_class).to receive(:resolve).with("nowhere.example").and_return([])
      allow(described_class).to receive(:resolve).with("internal.example").and_return(["10.0.0.5"])
      messages = %w[nowhere.example internal.example].map do |host|
        described_class.pinned_address("http://#{host}/")
      rescue described_class::UnsafeEndpoint => e
        e.message
      end
      expect(messages.uniq.length).to eq(1)
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
        .to raise_error(described_class::UnsafeEndpoint, "does not resolve to a public address")
      expect(builder).not_to have_received(:adapter)
    end

    it "raises for a name that resolves to a NAT64 address of a private host" do
      builder = double("Faraday::RackBuilder")
      allow(builder).to receive(:adapter)
      allow(described_class).to receive(:resolve).with("nat64.example").and_return(["64:ff9b::a00:1"])

      expect { described_class.pin(builder, "http://nat64.example/") }
        .to raise_error(described_class::UnsafeEndpoint)
      expect(builder).not_to have_received(:adapter)
    end
  end

  describe ".same_destination?" do
    it "matches URLs that differ only in scheme or host case, an explicit default port or a trailing slash" do
      expect(described_class.same_destination?("HTTPS://Ollama.Example.test:443/v1/", "https://ollama.example.test/v1")).to eq(true)
      expect(described_class.same_destination?(" http://localhost:11434/v1 ", "http://localhost:11434/v1/")).to eq(true)
      expect(described_class.same_destination?("http://ollama.example.test", "http://ollama.example.test:80/")).to eq(true)
    end

    it "tells apart URLs with a different scheme, host, port or path" do
      expect(described_class.same_destination?("http://ollama.example.test/v1", "https://ollama.example.test/v1")).to eq(false)
      expect(described_class.same_destination?("https://attacker.example.test/v1", "https://ollama.example.test/v1")).to eq(false)
      expect(described_class.same_destination?("https://ollama.example.test:8443/v1", "https://ollama.example.test/v1")).to eq(false)
      expect(described_class.same_destination?("https://ollama.example.test/proxy/v1", "https://ollama.example.test/v1")).to eq(false)
    end

    it "never matches a missing or invalid URL" do
      expect(described_class.same_destination?(nil, nil)).to eq(false)
      expect(described_class.same_destination?("", "")).to eq(false)
      expect(described_class.same_destination?("not a url", "not a url")).to eq(false)
      expect(described_class.same_destination?("https://ollama.example.test/v1", nil)).to eq(false)
    end
  end
end
