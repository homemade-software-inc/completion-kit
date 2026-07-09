require "rails_helper"

RSpec.describe "CompletionKit provider credentials", type: :request do
  let(:base_path) { "/completion_kit/provider_credentials" }

  before do
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:available_models).and_return([{ id: "gpt-4.1" }])
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:configured?).and_return(true)
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
  end

  it "covers index, new, edit, create, update, and invalid branches" do
    credential = create(:completion_kit_provider_credential, provider: "openai")
    create(:completion_kit_provider_credential, provider: "ollama", api_key: "ollama-key")
    create(:completion_kit_model, provider: "ollama", model_id: "llama3", status: "active", supports_generation: true)

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OpenAI")
    expect(response.body).to include("0 models")
    expect(response.body).to include("1 models")

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)

    get "#{base_path}/#{credential.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { provider_credential: { provider: "anthropic", api_key: "anthropic-key", api_endpoint: "" } }
    end.to change(CompletionKit::ProviderCredential, :count).by(1)
    expect(response).to redirect_to("/completion_kit/provider_credentials")

    post base_path, params: { provider_credential: { provider: "", api_key: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{credential.id}", params: { provider_credential: { api_key: "new-key" } }
    expect(response).to redirect_to("/completion_kit/provider_credentials")
    expect(credential.reload.api_key).to eq("new-key")

    patch "#{base_path}/#{credential.id}", params: { provider_credential: { provider: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "creates an azure_foundry credential, persisting the api-version, and offers the field on the form" do
    get "#{base_path}/new"
    expect(response.body).to include("api_version")

    expect do
      post base_path, params: { provider_credential: {
        provider: "azure_foundry", api_key: "k",
        api_endpoint: "https://my-resource.openai.azure.com", api_version: "2024-10-21"
      } }
    end.to change(CompletionKit::ProviderCredential, :count).by(1)

    expect(CompletionKit::ProviderCredential.last.api_version).to eq("2024-10-21")
  end

  it "refresh action enqueues discovery job and returns ok" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(credential.id, force: true)

    post "#{base_path}/#{credential.id}/refresh"
    expect(response).to have_http_status(:ok)
  end

  it "refresh_all enqueues discovery for all credentials" do
    cred1 = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    cred2 = create(:completion_kit_provider_credential, provider: "ollama", api_key: "ollama-key")
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)

    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(cred1.id, force: true)
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(cred2.id, force: true)

    post "/completion_kit/refresh_models"
    expect(response).to have_http_status(:ok)
  end

  it "refresh_all sets discovering status on each credential" do
    cred = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)

    post "/completion_kit/refresh_models"
    cred.reload
    expect(cred.discovery_status).to eq("discovering")
  end

  it "statuses renders turbo streams reflecting the persisted discovery state" do
    cred = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    cred.update_columns(discovery_status: "discovering", discovery_current: 2, discovery_total: 5)

    get "#{base_path}/statuses", headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("discovery_status_#{cred.id}")
    expect(response.body).to include("provider_models_#{cred.id}")
    expect(response.body).to include("Checking models")
    expect(response.body).to include("2/5")
  end

  it "exposes the statuses polling url so the client polls the engine's actual mount path" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")

    get base_path
    expect(response.body).to include(%(data-ck-statuses-url="#{base_path}/statuses"))

    get "#{base_path}/#{credential.id}/edit"
    expect(response.body).to include(%(data-ck-statuses-url="#{base_path}/statuses"))
  end
end
