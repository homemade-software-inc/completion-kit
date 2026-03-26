require "rails_helper"

RSpec.describe "CompletionKit API reference", type: :request do
  it "renders the API reference page" do
    get "/completion_kit/api_reference"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("API")
    expect(response.body).to include("Authentication")
    expect(response.body).to include("Endpoints")
  end

  it "shows published prompts" do
    prompt = create(:completion_kit_prompt, name: "Summarizer", current: true)
    get "/completion_kit/api_reference"
    expect(response.body).to include("Summarizer")
    expect(response.body).to include(prompt.family_key)
  end

  it "shows masked API token when configured" do
    CompletionKit.config.api_token = "a-very-long-secret-token-here"
    get "/completion_kit/api_reference"
    expect(response.body).to include("a-ve")
    expect(response.body).to include("here")
    expect(response.body).not_to include("a-very-long-secret-token-here")
    CompletionKit.instance_variable_set(:@config, nil)
  end

  it "shows short token fully masked" do
    CompletionKit.config.api_token = "short"
    get "/completion_kit/api_reference"
    expect(response.body).to include("••••••••")
    expect(response.body).not_to include("short")
    CompletionKit.instance_variable_set(:@config, nil)
  end

  it "shows unconfigured message when no token" do
    get "/completion_kit/api_reference"
    expect(response.body).to include("No API token configured")
  end
end
