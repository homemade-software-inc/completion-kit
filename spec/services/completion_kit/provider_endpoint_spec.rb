require "rails_helper"

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
      allow(Resolv).to receive(:getaddresses).with("api.example").and_return(["93.184.216.34"])
      expect(described_class.validate("http://api.example/v1")).to eq([])
    end

    it "returns :invalid_url for a bad URL" do
      expect(described_class.validate("ftp://example.com")).to eq([:invalid_url])
      expect(described_class.validate("http://")).to eq([:invalid_url])
      expect(described_class.validate("http://e xample.com")).to eq([:invalid_url])
    end

    it "returns :unresolvable when DNS yields nothing" do
      allow(Resolv).to receive(:getaddresses).with("nowhere.example").and_return([])
      expect(described_class.validate("http://nowhere.example")).to eq([:unresolvable])
    end

    it "returns :unsafe_host for a private address" do
      expect(described_class.validate("http://10.0.0.5/")).to eq([:unsafe_host])
      expect(described_class.validate("http://192.168.1.10")).to eq([:unsafe_host])
    end

    it "returns :unsafe_host for a link-local address (cloud metadata)" do
      expect(described_class.validate("http://169.254.169.254/latest/meta-data")).to eq([:unsafe_host])
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

    it "is true for an unresolvable host (DNS failure shouldn't block the request)" do
      allow(Resolv).to receive(:getaddresses).with("nowhere.example").and_return([])
      expect(described_class.safe?("http://nowhere.example")).to eq(true)
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
end
