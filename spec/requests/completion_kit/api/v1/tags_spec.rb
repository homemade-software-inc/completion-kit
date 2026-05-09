require "rails_helper"

RSpec.describe "API V1 Tags", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/tags" do
    it "returns all tags ordered by name" do
      CompletionKit::Tag.create!(name: "beta")
      CompletionKit::Tag.create!(name: "alpha")
      get "/completion_kit/api/v1/tags", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.map { |t| t["name"] }).to eq(["alpha", "beta"])
      expect(body.first["color"]).to be_a(String)
    end
  end

  describe "GET /api/v1/tags/:id" do
    it "returns the tag" do
      tag = CompletionKit::Tag.create!(name: "alpha")
      get "/completion_kit/api/v1/tags/#{tag.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("alpha")
    end

    it "returns 404 for missing tag" do
      get "/completion_kit/api/v1/tags/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/tags" do
    it "creates a tag with autoassigned color" do
      expect do
        post "/completion_kit/api/v1/tags",
          params: {name: "fresh"}.to_json,
          headers: headers
      end.to change(CompletionKit::Tag, :count).by(1)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["color"]).to be_a(String)
    end

    it "ignores color in the request body (read-only)" do
      post "/completion_kit/api/v1/tags",
        params: {name: "manual", color: "amethyst"}.to_json,
        headers: headers
      tag = CompletionKit::Tag.find_by!(name: "manual")
      expect(tag.color).not_to eq("amethyst")
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/tags",
        params: {name: ""}.to_json,
        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/tags/:id" do
    it "updates the tag name" do
      tag = CompletionKit::Tag.create!(name: "alpha")
      patch "/completion_kit/api/v1/tags/#{tag.id}",
        params: {name: "alpha-renamed"}.to_json,
        headers: headers
      expect(response).to have_http_status(:ok)
      expect(tag.reload.name).to eq("alpha-renamed")
    end

    it "returns 422 when invalid" do
      tag = CompletionKit::Tag.create!(name: "alpha")
      patch "/completion_kit/api/v1/tags/#{tag.id}",
        params: {name: ""}.to_json,
        headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/tags/:id" do
    it "deletes the tag" do
      tag = CompletionKit::Tag.create!(name: "alpha")
      expect do
        delete "/completion_kit/api/v1/tags/#{tag.id}", headers: headers
      end.to change(CompletionKit::Tag, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
