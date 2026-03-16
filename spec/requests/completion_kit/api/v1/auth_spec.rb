require "rails_helper"

RSpec.describe "API Authentication", type: :request do
  after { CompletionKit.instance_variable_set(:@config, nil) }

  context "when no api_token is configured" do
    before { CompletionKit.config.api_token = nil }

    it "returns 401 with 'API token not configured'" do
      get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Bearer anything"}
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq({"error" => "API token not configured"})
    end
  end

  context "when api_token is configured" do
    before { CompletionKit.config.api_token = "test-secret-token" }

    it "returns 401 when no Authorization header provided" do
      get "/completion_kit/api/v1/prompts"
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq({"error" => "Unauthorized"})
    end

    it "returns 401 when token is wrong" do
      get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Bearer wrong-token"}
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)).to eq({"error" => "Unauthorized"})
    end

    it "returns 401 when Authorization header has wrong scheme" do
      get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Basic dXNlcjpwYXNz"}
      expect(response).to have_http_status(:unauthorized)
    end

    it "allows access with correct token" do
      get "/completion_kit/api/v1/prompts", headers: {"Authorization" => "Bearer test-secret-token"}
      expect(response).to have_http_status(:ok)
    end
  end
end
