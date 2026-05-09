require "rails_helper"

RSpec.describe CompletionKit::McpTools::Tags do
  it "lists tags" do
    CompletionKit::Tag.create!(name: "alpha")
    result = described_class.call("tags_list", {})
    text = result[:content].first[:text]
    expect(text).to include("alpha")
  end

  it "creates a tag" do
    expect do
      described_class.call("tags_create", { "name" => "fresh" })
    end.to change(CompletionKit::Tag, :count).by(1)
  end

  it "returns isError when create fails" do
    result = described_class.call("tags_create", { "name" => "" })
    expect(result[:isError]).to be(true)
  end

  it "gets a tag by id" do
    tag = CompletionKit::Tag.create!(name: "alpha")
    result = described_class.call("tags_get", { "id" => tag.id })
    expect(result[:content].first[:text]).to include("alpha")
  end

  it "updates a tag" do
    tag = CompletionKit::Tag.create!(name: "alpha")
    described_class.call("tags_update", { "id" => tag.id, "name" => "beta" })
    expect(tag.reload.name).to eq("beta")
  end

  it "returns isError on update failure" do
    tag = CompletionKit::Tag.create!(name: "alpha")
    result = described_class.call("tags_update", { "id" => tag.id, "name" => "" })
    expect(result[:isError]).to be(true)
  end

  it "deletes a tag" do
    tag = CompletionKit::Tag.create!(name: "alpha")
    expect do
      described_class.call("tags_delete", { "id" => tag.id })
    end.to change(CompletionKit::Tag, :count).by(-1)
  end

  it "exposes tool definitions" do
    names = described_class.definitions.map { |t| t[:name] }
    expect(names).to match_array(%w[tags_list tags_get tags_create tags_update tags_delete])
  end
end

RSpec.describe CompletionKit::McpDispatcher do
  it "routes tags_* to McpTools::Tags" do
    CompletionKit::Tag.create!(name: "alpha")
    result = described_class.dispatch("tools/call",
      { "name" => "tags_list", "arguments" => {} })
    expect(result[:content].first[:text]).to include("alpha")
  end

  it "includes tags in tools/list" do
    list = described_class.dispatch("tools/list", {})
    names = list[:tools].map { |t| t[:name] }
    expect(names).to include("tags_list")
  end
end
