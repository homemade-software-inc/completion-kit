require "rails_helper"

RSpec.describe CompletionKit::TagFiltering, type: :controller do
  controller(CompletionKit::ApplicationController) do
    include CompletionKit::TagFiltering

    skip_before_action :authenticate_completion_kit!, raise: false

    def index
      tags = filter_tags_from_params
      render json: { ids: tags.map(&:id), names: tags.map(&:name) }
    end
  end

  let!(:marine) { CompletionKit::Tag.create!(name: "marine biology") }
  let!(:realty) { CompletionKit::Tag.create!(name: "real estate") }

  it "returns [] when no tag param is given" do
    get :index
    expect(JSON.parse(response.body)["ids"]).to eq([])
  end

  it "returns [] when tag param is blank" do
    get :index, params: { tag: [""] }
    expect(JSON.parse(response.body)["ids"]).to eq([])
  end

  it "resolves a single tag name to its record" do
    get :index, params: { tag: ["marine biology"] }
    expect(JSON.parse(response.body)["names"]).to eq(["marine biology"])
  end

  it "resolves multiple tag names" do
    get :index, params: { tag: ["marine biology", "real estate"] }
    expect(JSON.parse(response.body)["ids"]).to match_array([marine.id, realty.id])
  end

  it "ignores unknown tag names silently" do
    get :index, params: { tag: ["marine biology", "nonexistent"] }
    expect(JSON.parse(response.body)["names"]).to eq(["marine biology"])
  end

  it "normalizes case and whitespace" do
    get :index, params: { tag: ["  Marine Biology  "] }
    expect(JSON.parse(response.body)["names"]).to eq(["marine biology"])
  end
end
