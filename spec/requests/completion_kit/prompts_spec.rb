require "rails_helper"

RSpec.describe "CompletionKit prompts", type: :request do
  let(:base_path) { "/completion_kit/prompts" }
  let!(:metric_group) { create(:completion_kit_metric_group, :with_metrics) }
  let(:valid_params) do
    {
      prompt: {
        name: "Email Summarizer",
        description: "Summarizes support emails",
        template: "Summarize {{content}}",
        llm_model: "gpt-4.1",
        assessment_model: "gpt-4o-mini",
        metric_group_id: metric_group.id
      }
    }
  end

  it "renders the engine root and prompts index" do
    prompt = create(:completion_kit_prompt, name: "Root Prompt")

    get "/completion_kit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("CompletionKit")
    expect(response.body).to include(prompt.name)
  end

  it "renders show, new, and edit pages" do
    prompt = create(:completion_kit_prompt, name: "Visible Prompt")

    get "#{base_path}/#{prompt.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Support summary")
    expect(response.body).to include("Review notes")
    expect(response.body).to include(metric_group.name)

    get "#{base_path}/#{prompt.id}/edit"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible Prompt")
  end

  it "creates a prompt with valid params" do
    expect do
      post base_path, params: valid_params
    end.to change(CompletionKit::Prompt, :count).by(1)

    expect(response).to redirect_to("/completion_kit/prompts/#{CompletionKit::Prompt.last.id}")
    expect(CompletionKit::Prompt.last.metric_group).to eq(metric_group)
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

  it "creates a new version instead of mutating a prompt with existing runs" do
    prompt = create(:completion_kit_prompt, name: "Versioned Prompt", family_key: "family-1", version_number: 1)
    create(:completion_kit_test_run, prompt: prompt)

    expect do
      patch "#{base_path}/#{prompt.id}", params: { prompt: { name: "Versioned Prompt", template: "Updated {{content}}", llm_model: "gpt-4o", assessment_model: "gpt-4o-mini" } }
    end.to change(CompletionKit::Prompt, :count).by(1)

    expect(response).to redirect_to(%r{/completion_kit/prompts/\d+/edit})
    expect(prompt.reload.template).to eq("Summarize {{content}} for {{audience}}")
    expect(CompletionKit::Prompt.order(:id).last.version_number).to eq(2)
  end

  it "publishes a version as current" do
    current_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 1, current: true)
    draft_prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-2", version_number: 2, current: false, published_at: nil)

    post "/completion_kit/prompts/#{draft_prompt.id}/publish"

    expect(response).to redirect_to("/completion_kit/prompts/#{draft_prompt.id}")
    expect(current_prompt.reload.current).to eq(false)
    expect(draft_prompt.reload.current).to eq(true)
  end

  it "creates a new draft version from an existing version" do
    prompt = create(:completion_kit_prompt, name: "Family Prompt", family_key: "family-3", version_number: 1)

    expect do
      post "/completion_kit/prompts/#{prompt.id}/new_version"
    end.to change(CompletionKit::Prompt, :count).by(1)

    new_prompt = CompletionKit::Prompt.order(:id).last
    expect(response).to redirect_to("/completion_kit/prompts/#{new_prompt.id}/edit")
    expect(new_prompt.current).to eq(false)
    expect(new_prompt.version_number).to eq(2)
  end

  it "destroys a prompt" do
    prompt = create(:completion_kit_prompt)

    expect do
      delete "#{base_path}/#{prompt.id}"
    end.to change(CompletionKit::Prompt, :count).by(-1)

    expect(response).to redirect_to("/completion_kit/prompts")
  end
end
