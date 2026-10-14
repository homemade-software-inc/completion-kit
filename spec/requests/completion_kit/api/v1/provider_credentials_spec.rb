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
      expect(JSON.parse(response.body)).to have_key("details")
    end
  end

  describe "PATCH /api/v1/provider_credentials/:id moving a stored key" do
    before { allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"]) }

    let!(:cred) do
      create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-stored-secret")
    end

    it "rejects a new endpoint without api_key and queues no discovery" do
      ollama = create(:completion_kit_provider_credential, provider: "ollama", api_key: "ollama-secret",
        api_endpoint: "https://ollama.example.test")
      expect(CompletionKit::ModelDiscoveryJob).not_to receive(:perform_later)

      patch "/completion_kit/api/v1/provider_credentials/#{ollama.id}",
        params: {api_endpoint: "https://elsewhere.example.test"}.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["details"]["api_key"].join).to match(/entered again/)
      ollama.reload
      expect(ollama.api_endpoint).to eq("https://ollama.example.test")
      expect(ollama.api_key).to eq("ollama-secret")
    end

    it "rejects a provider switch without api_key" do
      expect(CompletionKit::ModelDiscoveryJob).not_to receive(:perform_later)

      patch "/completion_kit/api/v1/provider_credentials/#{cred.id}",
        params: {provider: "ollama", api_endpoint: "https://elsewhere.example.test"}.to_json,
        headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      cred.reload
      expect(cred.provider).to eq("openai")
      expect(cred.api_endpoint).to be_nil
      expect(cred.api_key).to eq("sk-stored-secret")
    end

    it "accepts a new endpoint sent with api_key" do
      patch "/completion_kit/api/v1/provider_credentials/#{cred.id}",
        params: {api_endpoint: "https://elsewhere.example.test", api_key: "sk-for-elsewhere"}.to_json,
        headers: headers

      expect(response).to have_http_status(:ok)
      cred.reload
      expect(cred.api_endpoint).to eq("https://elsewhere.example.test")
      expect(cred.api_key).to eq("sk-for-elsewhere")
    end
  end

  describe "azure_foundry api-version" do
    before { allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"]) }

    it "accepts api_version on create and returns it (without the key)" do
      post "/completion_kit/api/v1/provider_credentials",
        params: { provider: "azure_foundry", api_key: "k",
                  api_endpoint: "https://my-resource.openai.azure.com", api_version: "2024-10-21" }.to_json,
        headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["api_version"]).to eq("2024-10-21")
      expect(body).not_to have_key("api_key")
    end
  end

  describe "DELETE /api/v1/provider_credentials/:id" do
    it "deletes an unused credential and its discovered models" do
      cred = create(:completion_kit_provider_credential, provider: "openai")
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)

      delete "/completion_kit/api/v1/provider_credentials/#{cred.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(CompletionKit::Model.where(provider: "openai")).not_to exist
    end

    it "refuses to delete an in-use credential with 422" do
      cred = create(:completion_kit_provider_credential, provider: "openai")
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)
      create(:completion_kit_prompt, llm_model: "gpt-4.1")

      delete "/completion_kit/api/v1/provider_credentials/#{cred.id}", headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("details")
      expect(CompletionKit::ProviderCredential.exists?(cred.id)).to be(true)
    end
  end
end
