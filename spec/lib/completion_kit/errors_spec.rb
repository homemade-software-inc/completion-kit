require "rails_helper"

RSpec.describe CompletionKit::RateLimitError do
  it "carries provider, status, and retry_after attributes" do
    error = described_class.new("rate limited", provider: "openai", status: 429, retry_after: 30)
    expect(error.message).to eq("rate limited")
    expect(error.provider).to eq("openai")
    expect(error.status).to eq(429)
    expect(error.retry_after).to eq(30)
  end

  it "subclasses StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end
end

RSpec.describe CompletionKit::ConfigurationError do
  it "subclasses StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end
end

RSpec.describe CompletionKit::EndpointError do
  before { allow(Rails.logger).to receive(:warn) }

  TransportErrors.samples.each do |label, (error, message)|
    it "turns #{label} into one fixed message that names no host, port or banner" do
      result = described_class.from(error)

      expect(result).to be_a(described_class)
      expect(result.message).to eq(message)
      expect(TransportErrors.leaks?(result.message)).to be(false)
    end
  end

  it "treats any subclass of a Faraday timeout as a timeout" do
    stub_const("SlowReadTimeout", Class.new(Faraday::TimeoutError))

    expect(described_class.from(SlowReadTimeout.new("Net::ReadTimeout 10.9.8.7:443")).message)
      .to eq("The endpoint did not respond in time.")
  end

  it "keeps the connection and timeout messages apart" do
    expect(described_class::TIMEOUT_MESSAGE).not_to eq(described_class::CONNECTION_MESSAGE)
  end

  it "returns any other error untouched" do
    error = ArgumentError.new("bad")

    expect(described_class.from(error)).to be(error)
  end
end
