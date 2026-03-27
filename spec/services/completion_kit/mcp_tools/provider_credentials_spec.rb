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

    it "updates a credential" do
      result = described_class.call("provider_credentials_update", {
        "id" => credential.id, "api_endpoint" => "https://custom.api"
      })
      content = JSON.parse(result[:content].first[:text])
      expect(content["api_endpoint"]).to eq("https://custom.api")
    end

    it "returns error on invalid create" do
      result = described_class.call("provider_credentials_create", {"provider" => ""})
      expect(result[:isError]).to be true
    end

    it "returns error on invalid update" do
      result = described_class.call("provider_credentials_update", {"id" => credential.id, "provider" => ""})
      expect(result[:isError]).to be true
    end

    it "deletes a credential" do
      result = described_class.call("provider_credentials_delete", {"id" => credential.id})
      expect(result[:content].first[:text]).to include("deleted")
    end
  end
end
