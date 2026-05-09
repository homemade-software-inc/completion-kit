require "rails_helper"

RSpec.describe "CompletionKit tags", type: :request do
  let(:base_path) { "/completion_kit/tags" }

  it "covers index, new, edit, create, update, invalid branches, and destroy" do
    tag = CompletionKit::Tag.create!(name: "marine biology")

    get base_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("marine biology")

    get "#{base_path}/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tag name")

    get "#{base_path}/#{tag.id}/edit"
    expect(response).to have_http_status(:ok)

    expect do
      post base_path, params: { tag: { name: "real estate" } }
    end.to change(CompletionKit::Tag, :count).by(1)
    expect(response).to redirect_to(base_path)

    post base_path, params: { tag: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    patch "#{base_path}/#{tag.id}", params: { tag: { name: "ocean biology" } }
    expect(response).to redirect_to(base_path)
    expect(tag.reload.name).to eq("ocean biology")

    patch "#{base_path}/#{tag.id}", params: { tag: { name: "" } }
    expect(response).to have_http_status(:unprocessable_entity)

    expect do
      delete "#{base_path}/#{tag.id}"
    end.to change(CompletionKit::Tag, :count).by(-1)
    expect(response).to redirect_to(base_path)
  end

  it "shows tagging counts on the index" do
    tag = CompletionKit::Tag.create!(name: "x")
    metric = create(:completion_kit_metric)
    CompletionKit::Tagging.create!(tag: tag, taggable: metric)
    get base_path
    expect(response.body).to include("1")
  end
end
