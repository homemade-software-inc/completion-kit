require "rails_helper"

RSpec.describe "CompletionKit provider credentials", type: :request do
  let(:base_path) { "/completion_kit/provider_credentials" }

  before do
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:available_models).and_return([{ id: "gpt-4.1" }])
    allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:configured?).and_return(true)
    allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
    allow(CompletionKit::ProviderEndpoint).to receive(:resolve).and_return(["93.184.216.34"])
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

  it "offers a refresh control on the edit page when a provider has no models yet" do
    credential = create(:completion_kit_provider_credential, provider: "openai")
    credential.update_columns(discovery_status: "completed")

    get "#{base_path}/#{credential.id}/edit"
    expect(response.body).to include("Available models")
    expect(response.body).to include("ck-model-list__summary-count")
    expect(response.body).to include("ck-model-list__refresh")
  end

  it "shows the Azure Foundry catalog deploy-more line when a catalog count is known" do
    azure = create(:completion_kit_provider_credential, provider: "azure_foundry", api_key: "k",
      api_endpoint: "https://res.example.test/api/projects/notes")
    azure.update_columns(catalog_model_count: 228, discovery_status: "completed")

    get "#{base_path}/#{azure.id}/edit"
    expect(response.body).to include("228 models available to deploy")
    expect(response.body).to include("ck-model-list__catalog-link")
    expect(response.body).to include("ai.azure.com")
  end

  it "hides the API version field unless the Azure provider is selected" do
    openai = create(:completion_kit_provider_credential, provider: "openai")
    get "#{base_path}/#{openai.id}/edit"
    field = Nokogiri::HTML5(response.body).at_css('[data-ck-provider-field="azure_foundry"]')
    expect(field).to be_present
    expect(field.key?("hidden")).to be(true)

    azure = create(:completion_kit_provider_credential, provider: "azure_foundry", api_key: "k",
      api_endpoint: "https://my-resource.openai.azure.com", api_version: "2024-10-21")
    get "#{base_path}/#{azure.id}/edit"
    field = Nokogiri::HTML5(response.body).at_css('[data-ck-provider-field="azure_foundry"]')
    expect(field.key?("hidden")).to be(false)
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

  describe "destroy" do
    it "destroys an unused provider and its discovered models, redirecting with a notice" do
      credential = create(:completion_kit_provider_credential, provider: "openai")
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)

      expect { delete "#{base_path}/#{credential.id}" }
        .to change(CompletionKit::ProviderCredential, :count).by(-1)

      expect(response).to redirect_to(base_path)
      expect(flash[:notice]).to match(/removed/i)
      expect(CompletionKit::Model.where(provider: "openai")).not_to exist
    end

    it "refuses to destroy an in-use provider, leaving it intact with an alert" do
      credential = create(:completion_kit_provider_credential, provider: "openai")
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)
      create(:completion_kit_prompt, llm_model: "gpt-4.1")

      expect { delete "#{base_path}/#{credential.id}" }
        .not_to change(CompletionKit::ProviderCredential, :count)

      expect(response).to redirect_to(base_path)
      expect(flash[:alert]).to match(/in use/i)
    end

    it "shows a delete control on the edit page for an unused provider" do
      credential = create(:completion_kit_provider_credential, provider: "openai")
      get "#{base_path}/#{credential.id}/edit"
      expect(response.body).to include("Delete provider")
    end

    it "shows an enabled delete control for an in-use provider without a persistent in-use notice (the server rejects on attempt)" do
      credential = create(:completion_kit_provider_credential, provider: "openai")
      create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1", status: "active", supports_generation: true)
      create(:completion_kit_prompt, llm_model: "gpt-4.1")

      get "#{base_path}/#{credential.id}/edit"
      expect(response.body).not_to match(/in use/i)

      doc = Nokogiri::HTML5(response.body)
      target = "#{base_path}/#{credential.id}"
      delete_form = doc.css("form").select { |f| f["action"] == target }
                       .find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "delete" } }
      trigger = doc.at_css("button[aria-label='Delete provider']")

      expect(delete_form).to be_present
      expect(trigger).to be_present
      expect(trigger.key?("disabled")).to be(false)
      expect(trigger["form"]).to eq(delete_form["id"])
    end

    it "renders the delete control as its own form, not nested in the edit form (so it issues DELETE, not a Turbo-swallowed PATCH)" do
      credential = create(:completion_kit_provider_credential, provider: "openai")

      get "#{base_path}/#{credential.id}/edit"

      doc = Nokogiri::HTML5(response.body)
      target = "#{base_path}/#{credential.id}"
      forms = doc.css("form").select { |f| f["action"] == target }
      patch_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "patch" } }
      delete_form = forms.find { |f| f.css("input[name='_method']").any? { |i| i["value"] == "delete" } }

      expect(patch_form).to be_present
      expect(delete_form).to be_present
      expect(patch_form).not_to eq(delete_form)

      expect(delete_form["id"]).to be_present
      trigger = doc.at_css("button[type='submit'][form='#{delete_form["id"]}']")
      expect(trigger).to be_present
      expect(trigger["aria-label"]).to eq("Delete provider")
      expect(trigger["data-turbo-confirm"]).to be_present
    end
  end

  it "exposes the statuses polling url so the client polls the engine's actual mount path" do
    credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")

    get base_path
    expect(response.body).to include(%(data-ck-statuses-url="#{base_path}/statuses"))

    get "#{base_path}/#{credential.id}/edit"
    expect(response.body).to include(%(data-ck-statuses-url="#{base_path}/statuses"))
  end

  it "keeps a key typed into a failed create so it need not be pasted again" do
    post base_path, params: { provider_credential: { provider: "azure_foundry", api_key: "sk-typed-new-key", api_endpoint: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Nokogiri::HTML5(response.body).at_css("textarea[name='provider_credential[api_key]']").text.strip).to eq("sk-typed-new-key")
  end

  describe "the key on the providers list" do
    def card_key(provider_credential)
      doc = Nokogiri::HTML5(response.body)
      doc.at_css("a.ck-provider-card[href='#{base_path}/#{provider_credential.id}/edit'] .ck-provider-card__key").text
    end

    it "shows no more of a long key than its last four characters" do
      credential = create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-live-LONGSECRET-9z8y")

      get base_path

      expect(card_key(credential)).to eq("#{'•' * 12}9z8y")
      expect(response.body).not_to include("sk-live")
    end

    it "shows only dots for a short key" do
      credential = create(:completion_kit_provider_credential, provider: "openrouter", api_key: "short12")

      get base_path

      expect(card_key(credential)).to eq("•" * 12)
      expect(response.body).not_to include("short12")
      expect(response.body).not_to include("rt12")
    end

    it "says there is no key, without an em dash, when none is stored" do
      credential = create(:completion_kit_provider_credential, provider: "ollama", api_key: nil)

      get base_path

      expect(card_key(credential)).to eq("No key")
      expect(Nokogiri::HTML5(response.body).at_css(".ck-provider-list").text).not_to include("—")
    end
  end

  describe "the stored API key on the edit form" do
    let(:stored_key) { "sk-live-STOREDSECRET-1a2b" }
    let!(:credential) do
      create(:completion_kit_provider_credential, provider: "ollama", api_key: stored_key,
        api_endpoint: "https://ollama.example.test")
    end
    let(:form_params) do
      { provider: "ollama", api_key: "", api_endpoint: "https://ollama.example.test", api_version: "" }
    end

    it "never renders the stored key, showing only its last four characters" do
      get "#{base_path}/#{credential.id}/edit"

      expect(response.body).not_to include(stored_key)
      doc = Nokogiri::HTML5(response.body)
      expect(doc.at_css("textarea[name='provider_credential[api_key]']").text.strip).to eq("")
      expect(response.body).to include("ending in <code>1a2b</code>")
      box = doc.at_css("input[type='checkbox'][name='provider_credential[remove_api_key]']")
      expect(box).to be_present
      expect(box.key?("checked")).to be(false)
    end

    it "offers no ending hint or remove option when no key is stored" do
      keyless = create(:completion_kit_provider_credential, provider: "openrouter", api_key: nil)

      get "#{base_path}/#{keyless.id}/edit"

      expect(response.body).not_to include("ending in")
      expect(response.body).not_to include("provider_credential[remove_api_key]")
    end

    it "keeps the stored key when the field is left blank and nothing else moves" do
      patch "#{base_path}/#{credential.id}", params: { provider_credential: form_params }

      expect(response).to redirect_to(base_path)
      expect(credential.reload.api_key).to eq(stored_key)
    end

    it "replaces the stored key with a new one" do
      patch "#{base_path}/#{credential.id}", params: { provider_credential: form_params.merge(api_key: "sk-replacement") }

      expect(response).to redirect_to(base_path)
      expect(credential.reload.api_key).to eq("sk-replacement")
    end

    it "clears the key when the remove option is ticked" do
      patch "#{base_path}/#{credential.id}", params: { provider_credential: form_params.merge(remove_api_key: "1") }

      expect(response).to redirect_to(base_path)
      expect(credential.reload.api_key).to be_nil
    end

    context "when the host app raises on unpermitted parameters" do
      around do |example|
        original = ActionController::Parameters.action_on_unpermitted_parameters
        ActionController::Parameters.action_on_unpermitted_parameters = :raise
        example.run
      ensure
        ActionController::Parameters.action_on_unpermitted_parameters = original
      end

      it "clears the key when the remove option is ticked" do
        patch "#{base_path}/#{credential.id}", params: { provider_credential: form_params.merge(remove_api_key: "1") }

        expect(response).to redirect_to(base_path)
        expect(credential.reload.api_key).to be_nil
      end

      it "keeps the stored key when the remove option is left unticked" do
        patch "#{base_path}/#{credential.id}", params: { provider_credential: form_params.merge(remove_api_key: "0") }

        expect(response).to redirect_to(base_path)
        expect(credential.reload.api_key).to eq(stored_key)
      end
    end

    it "saves a typed key over the ticked remove option" do
      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(api_key: "sk-replacement", remove_api_key: "1") }

      expect(response).to redirect_to(base_path)
      expect(credential.reload.api_key).to eq("sk-replacement")
    end

    it "keeps the remove option ticked when the save fails" do
      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(provider: "azure_foundry", api_endpoint: "", remove_api_key: "1") }

      expect(response).to have_http_status(:unprocessable_entity)
      box = Nokogiri::HTML5(response.body).at_css("input[type='checkbox'][name='provider_credential[remove_api_key]']")
      expect(box.key?("checked")).to be(true)
      expect(credential.reload.api_key).to eq(stored_key)
    end

    it "unticks the remove option when a typed key wins but the save fails" do
      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(provider: "azure_foundry", api_endpoint: "", api_key: "sk-replacement", remove_api_key: "1") }

      expect(response).to have_http_status(:unprocessable_entity)
      box = Nokogiri::HTML5(response.body).at_css("input[type='checkbox'][name='provider_credential[remove_api_key]']")
      expect(box.key?("checked")).to be(false)
    end

    it "offers the remove option without an ending hint for a short stored key" do
      short = create(:completion_kit_provider_credential, provider: "openrouter", api_key: "k3y9x")

      get "#{base_path}/#{short.id}/edit"

      expect(response.body).not_to include("k3y9x")
      expect(response.body).not_to include("ending in")
      expect(response.body).to include("Leave blank to keep the current key.")
      expect(Nokogiri::HTML5(response.body).at_css("input[type='checkbox'][name='provider_credential[remove_api_key]']")).to be_present
    end

    it "leaves the remove option unticked when the save fails without it" do
      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(provider: "azure_foundry", api_endpoint: "") }

      expect(response).to have_http_status(:unprocessable_entity)
      box = Nokogiri::HTML5(response.body).at_css("input[type='checkbox'][name='provider_credential[remove_api_key]']")
      expect(box.key?("checked")).to be(false)
    end

    it "rejects a new endpoint with a blank key, keeping the stored key and queueing no discovery" do
      expect(CompletionKit::ModelDiscoveryJob).not_to receive(:perform_later)

      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(api_endpoint: "https://elsewhere.example.test") }

      expect(response).to have_http_status(:unprocessable_entity)
      field = Nokogiri::HTML5(response.body).at_css("textarea[name='provider_credential[api_key]']")
      expect(field["aria-invalid"]).to eq("true")
      expect(field.text.strip).to eq("")
      expect(response.body).not_to include(stored_key)
      credential.reload
      expect(credential.api_key).to eq(stored_key)
      expect(credential.api_endpoint).to eq("https://ollama.example.test")
    end

    it "rejects a new provider with a blank key" do
      expect(CompletionKit::ModelDiscoveryJob).not_to receive(:perform_later)

      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(provider: "azure_foundry") }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML5(response.body).at_css("textarea[name='provider_credential[api_key]']")["aria-invalid"]).to eq("true")
      expect(credential.reload.provider).to eq("ollama")
      expect(credential.api_key).to eq(stored_key)
    end

    it "accepts a new endpoint when a key is entered with it" do
      patch "#{base_path}/#{credential.id}",
        params: { provider_credential: form_params.merge(api_endpoint: "https://elsewhere.example.test", api_key: "sk-for-elsewhere") }

      expect(response).to redirect_to(base_path)
      credential.reload
      expect(credential.api_endpoint).to eq("https://elsewhere.example.test")
      expect(credential.api_key).to eq("sk-for-elsewhere")
    end
  end
end
