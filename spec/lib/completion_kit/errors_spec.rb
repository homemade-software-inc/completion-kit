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
