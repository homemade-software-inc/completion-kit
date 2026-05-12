require "rails_helper"

RSpec.describe "CompletionKit prompts", type: :request do
  let(:base_path) { "/completion_kit/prompts" }
  let(:valid_params) do
    {
      prompt: {
        name: "Email Summarizer",
        description: "Summarizes support emails",
        template: "Summarize {{content}}",
        llm_model: "gpt-4.1"
      }
    }
  end

  it "renders the prompts index" do
    prompt = create(:completion_kit_prompt, name: "Root Prompt")

    get base_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CompletionKit")
    expect(response.body).to include(prompt.name)
  end

  it "renders show, new, and edit pages" do
    prompt = create(:completion_kit_prompt, name: "Visible Prompt")

    get "#{base_path}/#{prompt.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")
    expect(response.body).not_to include("Changes from")

    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prompt text")
    expect(response.body).to include("OpenAI")

    get "#{base_path}/#{prompt.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")
    expect(response.body).not_to include("saving creates a new version")
  end

  it "shows a diff against the previous version when viewing a later version" do
    create(:completion_kit_prompt, name: "Diffed", family_key: "fam-diff", version_number: 1, current: false, template: "Summarise {{content}}.")
    v2 = create(:completion_kit_prompt, name: "Diffed", family_key: "fam-diff", version_number: 2, current: true, template: "Summarise {{content}} in two sentences.")

    get "#{base_path}/#{v2.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Changes from v1")
    expect(response.body).to include("ck-suggest-diff")
  end

  it "notes on the edit form that saving creates a new version once that version has runs" do
    prompt = create(:completion_kit_prompt)
    create(:completion_kit_run, prompt: prompt, dataset: create(:completion_kit_dataset))

    get "#{base_path}/#{prompt.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("saving creates a new version")
  end

  it "renders the model refresh button disabled and spinning while discovery is in progress" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test", discovery_status: "discovering")
    create(:completion_kit_model, provider: "openai", model_id: "gpt-4o", status: "active", supports_generation: true)

    get "#{base_path}/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<button[^>]*title="Refresh models"[^>]*\bdisabled\b/)
    expect(response.body).to match(/<button[^>]*class="[^"]*ck-icon-btn--spinning[^"]*"[^>]*title="Refresh models"/)
  end

  it "creates a prompt with valid params" do
    expect do
      post base_path, params: valid_params
    end.to change(CompletionKit::Prompt, :count).by(1)

    expect(response).to redirect_to("/completion_kit/prompts/#{CompletionKit::Prompt.last.id}")
  end

  it "renders new when create is invalid" do
    post base_path, params: { prompt: valid_params[:prompt].merge(name: "") }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this prompt from being saved")
  end

  it "updates a prompt with valid params" do
    prompt = create(:completion_kit_prompt, name: "Old Name")

    patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "New Name" } }

    expect(response).to redirect_to("/completion_kit/prompts/#{prompt.id}")
    expect(prompt.reload.name).to eq("New Name")
  end

  it "renders edit when update is invalid" do
    prompt = create(:completion_kit_prompt, name: "Old Name")

    patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("prevented this prompt from being saved")
  end

  it "creates a new version and publishes it when prompt has existing runs" do
    prompt = create(:completion_kit_prompt, name: "Versioned Prompt", family_key: "family-1", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "Versioned Prompt", template: "Updated {{content}}", llm_model: "gpt-4o" } }
    end.to change(CompletionKit::Prompt, :count).by(1)

    new_prompt = CompletionKit::Prompt.order(:id).last
    expect(response).to redirect_to(%r{/completion_kit/prompts/\d+})
    expect(prompt.reload.template).to eq("Summarize {{content}} for {{audience}}")
    expect(new_prompt.version_number).to eq(2)
    expect(new_prompt.current).to eq(true)
  end

  it "applies tag_names to the cloned version when prompt has existing runs" do
    prompt = create(:completion_kit_prompt, name: "Tagged Versioned", family_key: "family-tagged", version_number: 1)
    create(:completion_kit_run, prompt: prompt)

    patch "#{base_path}/#{prompt.id}", params: {
      prompt: { name: "Tagged Versioned", template: "Updated {{content}}",
                llm_model: "gpt-4o", tag_names: ["alpha"] }
    }

    new_prompt = CompletionKit::Prompt.order(:id).last
    expect(new_prompt.tag_names).to eq(["alpha"])
  end

  it "publishes a version as current" do
    current_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 1, current: true)
    draft_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 2, current: false, published_at: nil)

    post "/completion_kit/prompts/#{draft_prompt.id}/publish"

    expect(response).to redirect_to("/completion_kit/prompts/#{draft_prompt.id}")
    expect(current_prompt.reload.current).to eq(false)
    expect(draft_prompt.reload.current).to eq(true)
  end


  it "destroys a prompt" do
    prompt = create(:completion_kit_prompt)

    expect do
      delete "#{base_path}/#{prompt.id}"
    end.to change(CompletionKit::Prompt, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/prompts")
  end

  it "lists versions with a Make-current control for non-current ones, a Current badge for the current, and clickable rows" do
    v1 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 1, current: true, template: "v1 {{x}}")
    v2 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 2, current: false, template: "v2 {{x}}")

    get "/completion_kit/prompts/#{v1.id}"

    expect(response.body).to include("Current")
    expect(response.body).to include("Make current")
    expect(response.body).to include("/completion_kit/prompts/#{v2.id}")
  end

  it "round-trips tag_names on create and update" do
    post "/completion_kit/prompts", params: {
      prompt: { name: "P", template: "hi", llm_model: "gpt-4o-mini",
                tag_names: ["alpha"] }
    }
    prompt = CompletionKit::Prompt.find_by!(name: "P")
    expect(prompt.tag_names).to eq(["alpha"])

    patch "/completion_kit/prompts/#{prompt.id}", params: {
      prompt: { tag_names: [] }
    }
    expect(prompt.reload.tag_names).to eq([])
  end

  it "filters prompts by tag" do
    marine_prompt = create(:completion_kit_prompt, name: "Shark classifier")
    real_estate_prompt = create(:completion_kit_prompt, name: "Property listing writer")
    marine_prompt.update!(tag_names: ["marine biology"])
    real_estate_prompt.update!(tag_names: ["real estate"])

    get "/completion_kit/prompts?tag[]=marine biology"
    expect(response.body).to include("Shark classifier")
    expect(response.body).not_to include("Property listing writer")

    get "/completion_kit/prompts?tag[]=marine biology&tag[]=real estate"
    expect(response.body).to include("Shark classifier")
    expect(response.body).to include("Property listing writer")

    get "/completion_kit/prompts"
    expect(response.body).to include("Shark classifier")
    expect(response.body).to include("Property listing writer")
  end

  it "renders no filter bar when no tags exist" do
    create(:completion_kit_prompt, name: "Helpfulness")
    get "/completion_kit/prompts"
    expect(response.body).not_to include("Filter by tag")
  end

  it "shows the filter bar when tags exist" do
    CompletionKit::Tag.create!(name: "z")
    create(:completion_kit_prompt, name: "Helpfulness")
    get "/completion_kit/prompts"
    expect(response.body).to include("Filter by tag")
  end

end
