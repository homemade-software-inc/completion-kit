require "rails_helper"

RSpec.describe "API V1 Provider Credentials", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/provider_credentials" do
    it "returns all credentials without api_key" do
      create(:completion_kit_provider_credential, api_key: "secret-123")
      get "/completion_kit/api/v1/provider_credentials", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.first).not_to have_key("api_key")
    end
  end

  describe "GET /api/v1/provider_credentials/:id" do
    it "returns the credential without api_key" do
      cred = create(:completion_kit_provider_credential, api_key: "secret")
      get "/completion_kit/api/v1/provider_credentials/#{cred.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).not_to have_key("api_key")
    end

    it "returns 404 for missing credential" do
      get "/completion_kit/api/v1/provider_credentials/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/provider_credentials" do
    it "creates a credential" do
      post "/completion_kit/api/v1/provider_credentials",
        params: {provider: "openai", api_key: "sk-test123"}.to_json,
        headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["provider"]).to eq("openai")
      expect(body).not_to have_key("api_key")
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/provider_credentials", params: {provider: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/provider_credentials/:id" do
    it "updates the credential" do
      cred = create(:completion_kit_provider_credential)
      patch "/completion_kit/api/v1/provider_credentials/#{cred.id}",
        params: {api_key: "new-key"}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      expect(cred.reload.api_key).to eq("new-key")
    end

    it "returns 422 with invalid params" do
      cred = create(:completion_kit_provider_credential)
      patch "/completion_kit/api/v1/provider_credentials/#{cred.id}",
        params: {provider: "invalid-provider"}.to_json,
        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("errors")
    end
  end

  describe "DELETE /api/v1/provider_credentials/:id" do
    it "deletes the credential" do
      cred = create(:completion_kit_provider_credential)
      delete "/completion_kit/api/v1/provider_credentials/#{cred.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
