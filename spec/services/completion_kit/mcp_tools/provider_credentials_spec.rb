require "rails_helper"

RSpec.describe CompletionKit::McpTools::ProviderCredentials do
  describe ".definitions" do
    it "returns 5 tool definitions" do
      defs = described_class.definitions
      expect(defs.length).to eq(5)
      expect(defs.map { |d| d[:name] }).to match_array(%w[
        provider_credentials_list provider_credentials_get
        provider_credentials_create provider_credentials_update provider_credentials_delete
      ])
    end
  end

  describe ".call" do
    let!(:credential) { create(:completion_kit_provider_credential, provider: "openai") }

    before { allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"]) }

    it "lists provider credentials" do
      result = described_class.call("provider_credentials_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first["provider"]).to eq("openai")
    end

    it "does not expose api_key in list" do
      result = described_class.call("provider_credentials_list", {})
      content = JSON.parse(result[:content].first[:text])
      expect(content.first).not_to have_key("api_key")
    end

    it "gets a credential by id" do
      result = described_class.call("provider_credentials_get", {"id" => credential.id})
      content = JSON.parse(result[:content].first[:text])
      expect(content["id"]).to eq(credential.id)
    end

    it "creates a credential" do
      result = described_class.call("provider_credentials_create", {
        "provider" => "anthropic", "api_key" => "sk-test-123"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["provider"]).to eq("anthropic")
      expect(content).not_to have_key("api_key")
    end

    it "creates an azure_foundry credential with an api-version" do
      result = described_class.call("provider_credentials_create", {
        "provider" => "azure_foundry", "api_key" => "k",
        "api_endpoint" => "https://my-resource.openai.azure.com", "api_version" => "2024-10-21"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["provider"]).to eq("azure_foundry")
      expect(content["api_version"]).to eq("2024-10-21")
    end

    it "updates a credential's endpoint when the key is supplied with it" do
      result = described_class.call("provider_credentials_update", {
        "id" => credential.id, "api_endpoint" => "https://custom.api", "api_key" => "sk-for-custom"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["api_endpoint"]).to eq("https://custom.api")
      expect(credential.reload.api_key).to eq("sk-for-custom")
    end

    it "refuses a new endpoint without the key and queues no discovery" do
      expect(CompletionKit::ModelDiscoveryJob).not_to receive(:perform_later)

      result = described_class.call("provider_credentials_update", {
        "id" => credential.id, "api_endpoint" => "https://elsewhere.example.test"
      })

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to match(/api key/i)
      credential.reload
      expect(credential.api_endpoint).to be_nil
      expect(credential.api_key).to eq("test-key")
    end

    it "refuses a provider switch without the key" do
      result = described_class.call("provider_credentials_update", {
        "id" => credential.id, "provider" => "ollama", "api_endpoint" => "https://elsewhere.example.test"
      })

      expect(result[:isError]).to be true
      expect(credential.reload.provider).to eq("openai")
    end

    it "tells callers in the update schema that a new provider or endpoint needs the key" do
      definition = described_class.definitions.find { |d| d[:name] == "provider_credentials_update" }
      expect(definition[:description]).to match(/api_key/)
      expect(definition[:inputSchema][:properties][:api_key][:description]).to match(/provider or api_endpoint/)
    end

    it "returns error on invalid create" do
      result = described_class.call("provider_credentials_create", {"provider" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("provider_credentials_update", {"id" => credential.id, "provider" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes an unused credential and its discovered models" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)

      result = described_class.call("provider_credentials_delete", {"id" => credential.id})

      expect(result[:content].first[:text]).to include("deleted")
      expect(CompletionKit::Model.where(provider: "openai")).not_to exist
    end

    it "returns an error when the credential is still in use" do
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)
      create(:completion_kit_prompt, llm_model: "gpt-4.1")

      result = described_class.call("provider_credentials_delete", {"id" => credential.id})

      expect(result[:isError]).to be true
      expect(result[:content].first[:text]).to match(/in use/i)
      expect(CompletionKit::ProviderCredential.exists?(credential.id)).to be(true)
    end
  end
end
