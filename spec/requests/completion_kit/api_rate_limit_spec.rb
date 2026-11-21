require "rails_helper"

RSpec.describe "API rate limit key", type: :request do
  let(:keys) { [] }
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(CompletionKit::Api::V1::BaseController.cache_store).to receive(:increment) do |key, *args, **kwargs|
      keys << key
      store.increment(key, *args, **kwargs)
    end
  end

  after { CompletionKit.config.api_rate_limit_key = ->(request) { request.remote_ip } }

  it "keys the API rate limit on remote IP by default" do
    get "/completion_kit/api/v1/prompts", env: { "REMOTE_ADDR" => "203.0.113.7" }

    expect(keys.last).to end_with("203.0.113.7")
  end

  it "keys the API rate limit with the configured callable" do
    CompletionKit.config.api_rate_limit_key = ->(request) { "k-#{request.headers["X-Test"]}" }

    get "/completion_kit/api/v1/prompts", headers: { "X-Test" => "a" }

    expect(keys.last).to end_with("k-a")
  end
end
