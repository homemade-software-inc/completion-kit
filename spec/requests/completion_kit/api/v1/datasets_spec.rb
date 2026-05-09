require "rails_helper"

RSpec.describe "API V1 Datasets", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { {"Authorization" => "Bearer #{token}", "Content-Type" => "application/json"} }

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  describe "GET /api/v1/datasets" do
    it "returns all datasets" do
      create(:completion_kit_dataset)
      get "/completion_kit/api/v1/datasets", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe "GET /api/v1/datasets/:id" do
    it "returns the dataset" do
      dataset = create(:completion_kit_dataset)
      get "/completion_kit/api/v1/datasets/#{dataset.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(dataset.id)
    end

    it "returns 404 for missing dataset" do
      get "/completion_kit/api/v1/datasets/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/datasets" do
    it "creates a dataset" do
      post "/completion_kit/api/v1/datasets", params: {name: "test", csv_data: "col1,col2\na,b"}.to_json, headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns 422 with invalid params" do
      post "/completion_kit/api/v1/datasets", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/datasets/:id" do
    it "updates the dataset" do
      dataset = create(:completion_kit_dataset)
      patch "/completion_kit/api/v1/datasets/#{dataset.id}", params: {name: "updated"}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["name"]).to eq("updated")
    end

    it "returns 422 with invalid params" do
      dataset = create(:completion_kit_dataset)
      patch "/completion_kit/api/v1/datasets/#{dataset.id}", params: {name: ""}.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/datasets/:id" do
    it "deletes the dataset" do
      dataset = create(:completion_kit_dataset)
      delete "/completion_kit/api/v1/datasets/#{dataset.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "tag_names round-trip" do
    it "auto-creates new tags on POST and includes them in the response" do
      expect do
        post "/completion_kit/api/v1/datasets",
          params: { name: "D", csv_data: "col1\na", tag_names: ["new"] }.to_json,
          headers: headers
      end.to change(CompletionKit::Tag, :count).by(1)
      dataset = CompletionKit::Dataset.find_by!(name: "D")
      expect(dataset.tag_names).to eq(["new"])
      body = JSON.parse(response.body)
      expect(body["tags"].map { |t| t["name"] }).to eq(["new"])
    end

    it "replaces tags on PATCH" do
      dataset = create(:completion_kit_dataset)
      dataset.update!(tag_names: ["a", "b"])
      patch "/completion_kit/api/v1/datasets/#{dataset.id}",
        params: { tag_names: ["c"] }.to_json,
        headers: headers
      expect(dataset.reload.tag_names).to eq(["c"])
    end

    it "clears all tags on PATCH with empty array" do
      dataset = create(:completion_kit_dataset)
      dataset.update!(tag_names: ["a"])
      patch "/completion_kit/api/v1/datasets/#{dataset.id}",
        params: { tag_names: [] }.to_json,
        headers: headers
      expect(dataset.reload.tag_names).to eq([])
    end

    it "exposes tags in GET show" do
      dataset = create(:completion_kit_dataset)
      dataset.update!(tag_names: ["alpha"])
      get "/completion_kit/api/v1/datasets/#{dataset.id}", headers: headers
      body = JSON.parse(response.body)
      expect(body["tags"].map { |t| t["name"] }).to eq(["alpha"])
    end
  end
end
