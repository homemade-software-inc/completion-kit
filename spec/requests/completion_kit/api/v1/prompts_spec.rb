require "rails_helper"

RSpec.describe "API V1 Prompts", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/prompts" do
    it "returns all prompts ordered by created_at desc" do
      old = create(:completion_kit_prompt, created_at: 1.day.ago)
      recent = create(:completion_kit_prompt, created_at: 1.hour.ago)
      get "/completion_kit/api/v1/prompts", headers: headers
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |p| p["id"] }
      expect(ids).to eq([recent.id, old.id])
    end
  end

  describe "GET /api/v1/prompts/:id" do
    it "returns the prompt" do
      prompt = create(:completion_kit_prompt)
      get "/completion_kit/api/v1/prompts/#{prompt.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(prompt.id)
    end

    it "finds a prompt by slug (non-numeric id)" do
      prompt = create(:completion_kit_prompt, name: "My Cool Prompt")
      get "/completion_kit/api/v1/prompts/my-cool-prompt", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(prompt.id)
    end

    it "returns 404 for missing prompt" do
      get "/completion_kit/api/v1/prompts/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/prompts" do
    let(:valid_params) { {name: "test", template: "Hello {{name}}", llm_model: "gpt-4.1"} }

    it "creates a prompt" do
      post "/completion_kit/api/v1/prompts", params: valid_params.to_json, headers: headers
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["name"]).to eq("test")
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/prompts", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("errors")
    end
  end

  describe "PATCH /api/v1/prompts/:id" do
    let(:prompt) { create(:completion_kit_prompt) }

    it "updates the prompt" do
      patch "/completion_kit/api/v1/prompts/#{prompt.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      patch "/completion_kit/api/v1/prompts/#{prompt.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to have_key("errors")
    end
  end

  describe "DELETE /api/v1/prompts/:id" do
    it "deletes the prompt" do
      prompt = create(:completion_kit_prompt)
      delete "/completion_kit/api/v1/prompts/#{prompt.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(CompletionKit::Prompt.find_by(id: prompt.id)).to be_nil
    end
  end

  describe "POST /api/v1/prompts/:id/publish" do
    it "publishes the prompt version" do
      prompt = create(:completion_kit_prompt, current: false)
      post "/completion_kit/api/v1/prompts/#{prompt.id}/publish", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["current"]).to be true
    end
  end

  describe "PATCH /api/v1/prompts/:id auto-versioning" do
    it "creates a new version and publishes when prompt has runs" do
      prompt = create(:completion_kit_prompt)
      create(:completion_kit_run, prompt: prompt)

      patch "/completion_kit/api/v1/prompts/#{prompt.id}", params: {template: "Updated {{content}}"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["version_number"]).to eq(2)
      expect(body["current"]).to be true
      expect(prompt.reload.template).not_to eq("Updated {{content}}")
    end
  end
end
