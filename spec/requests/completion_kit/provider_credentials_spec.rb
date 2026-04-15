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

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OpenAI")

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

  it "refresh action enqueues discovery job and returns ok" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(credential.id)

    post "#{base_path}/#{credential.id}/refresh"
    expect(response).to have_http_status(:ok)
  end

  it "refresh_all enqueues discovery for all credentials" do
    cred1 = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    cred2 = create(:completion_kit_provider_credential, provider: "ollama", api_key: "ollama-key")
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)

    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(cred1.id)
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(cred2.id)

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
end
