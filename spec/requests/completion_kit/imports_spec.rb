require "rails_helper"

RSpec.describe "CompletionKit promptfoo import (web)", type: :request do
  let(:import_path) { "/completion_kit/import" }

  let(:yaml_full) do
    <<~YAML
      prompts:
        - "Summarize {{article}}."
      tests:
        - vars: { article: "x" }
      defaultTest:
        assert:
          - type: contains
            value: "summary"
          - type: llm-rubric
            value: "Is it concise?"
          - type: javascript
            value: "output.length < 100"
    YAML
  end

  let(:yaml_sparse) do
    <<~YAML
      prompts:
        - "file://main.txt"
      providers:
        - openai:gpt-4o
        - anthropic:claude-3-opus
    YAML
  end

  describe "GET /completion_kit/import" do
    it "renders the form with a textarea and a file input" do
      get import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("name=\"config\"")
      expect(response.body).to include("type=\"file\"")
      expect(response.body).to include("name=\"file\"")
    end
  end

  describe "POST /completion_kit/import" do
    it "imports a pasted config and summarizes created prompt, dataset, metrics, and skipped assert" do
      post import_path, params: { config: yaml_full }

      expect(response).to have_http_status(:ok)
      expect(CompletionKit::Prompt.count).to eq(1)
      expect(response.body).to include("Imported prompt 1")
      expect(response.body).to include("article")
      expect(response.body).to include("Check")
      expect(response.body).to include("Judge")
      expect(response.body).to include("javascript")
    end

    it "imports an uploaded file the same way" do
      upload = Rack::Test::UploadedFile.new(
        StringIO.new(yaml_full), "application/x-yaml", original_filename: "promptfooconfig.yaml"
      )

      post import_path, params: { file: upload }

      expect(response).to have_http_status(:ok)
      expect(CompletionKit::Prompt.count).to eq(1)
      expect(response.body).to include("Imported prompt 1")
    end

    it "summarizes skipped prompts, a skipped dataset, and matched/unmatched providers" do
      create(:completion_kit_provider_credential, provider: "openai")

      post import_path, params: { config: yaml_sparse }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("file://main.txt")
      expect(response.body).to include("no tests with vars to import")
      expect(response.body).to include("openai:gpt-4o")
      expect(response.body).to include("anthropic:claude-3-opus")
    end

    it "re-renders the form with the error for unparseable YAML and does not raise" do
      post import_path, params: { config: "x: : :" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("name=\"config\"")
      expect(response.body).to match(/Could not parse YAML/i)
      expect(CompletionKit::Prompt.count).to eq(0)
    end

    it "asks for input when neither config nor file is provided" do
      post import_path, params: {}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("name=\"config\"")
      expect(response.body).to match(/paste or upload/i)
    end
  end
end
