require "rails_helper"

RSpec.describe "CompletionKit API reference", type: :request do
  it "renders the API reference page with endpoint documentation" do
    get "/completion_kit/api_reference"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("API")
    expect(response.body).to include("Authentication")
    expect(response.body).to include("Prompts")
    expect(response.body).to include("Runs")
    expect(response.body).to include("Responses")
    expect(response.body).to include("Datasets")
    expect(response.body).to include("Metrics")
    expect(response.body).to include("Metric Groups")
    expect(response.body).to include("Provider Credentials")
    expect(response.body).to include("ck-api-endpoint")
    expect(response.body).to include("ck-api-copy")
  end

  it "shows published prompts" do
    create(:completion_kit_prompt, name: "Summarizer", current: true)
    get "/completion_kit/api_reference"
    expect(response.body).to include("Your prompts")
    expect(response.body).to include("Summarizer")
  end

  it "shows masked API token and includes real token in copy data" do
    CompletionKit.config.api_token = "a-very-long-secret-token-here"
    get "/completion_kit/api_reference"
    expect(response.body).to include("a-ve")
    expect(response.body).to include("here")
    expect(response.body).to include("data-real-token")
    CompletionKit.instance_variable_set(:@config, nil)
  end

  it "shows short token fully masked" do
    CompletionKit.config.api_token = "short"
    get "/completion_kit/api_reference"
    expect(response.body).to include("••••••••")
    CompletionKit.instance_variable_set(:@config, nil)
  end

  it "shows unconfigured message when no token" do
    get "/completion_kit/api_reference"
    expect(response.body).to include("No API token configured")
  end
end
