require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  it "throttles the REST API once the per-minute limit is exceeded" do
    limit = CompletionKit.config.api_rate_limit
    limit.times { get "/completion_kit/api/v1/prompts" }
    get "/completion_kit/api/v1/prompts"

    expect(response).to have_http_status(:too_many_requests)
    expect(JSON.parse(response.body)["error"]).to eq("Rate limit exceeded")
  end

  it "throttles engine pages once the per-minute limit is exceeded" do
    limit = CompletionKit.config.web_rate_limit
    limit.times { get "/completion_kit/prompts" }
    get "/completion_kit/prompts"

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("Rate limit exceeded")
  end
end
