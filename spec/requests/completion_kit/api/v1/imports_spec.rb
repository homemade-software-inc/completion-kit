require "rails_helper"

RSpec.describe "API V1 promptfoo import", type: :request do
  let(:token) { "test-api-token" }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:yaml) do
    <<~YAML
      prompts:
        - "Summarize {{article}}."
      tests:
        - vars: { article: "A long article" }
      defaultTest:
        assert:
          - type: contains
            value: "summary"
          - type: llm-rubric
            value: "Is it concise?"
    YAML
  end

  before { CompletionKit.config.api_token = token }
  after { CompletionKit.instance_variable_set(:@config, nil) }

  it "imports a config and returns a 201 summary" do
    post "/completion_kit/api/v1/imports/promptfoo", params: { config: yaml }.to_json, headers: headers

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["prompts"]["created"]).to eq(["Imported prompt 1"])
    expect(body["dataset"]["columns"]).to eq(["article"])
    expect(body["metrics"]["created"].map { |m| m["type"] }).to include("check", "llm_judge")
    expect(CompletionKit::Prompt.count).to eq(1)
  end

  it "accepts a raw YAML request body" do
    post "/completion_kit/api/v1/imports/promptfoo", params: yaml, headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "text/yaml" }

    expect(response).to have_http_status(:created)
  end

  it "returns 422 for unparseable YAML" do
    post "/completion_kit/api/v1/imports/promptfoo", params: { config: "x: : :" }.to_json, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "requires authentication" do
    post "/completion_kit/api/v1/imports/promptfoo", params: { config: yaml }.to_json, headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
