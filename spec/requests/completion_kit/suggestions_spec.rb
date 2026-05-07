require "rails_helper"

RSpec.describe "CompletionKit suggestions", type: :request do
  let(:prompt) { create(:completion_kit_prompt, name: "Static", template: "Static prompt") }
  let(:run) { create(:completion_kit_run, prompt: prompt) }
  let(:suggestion) do
    CompletionKit::Suggestion.create!(
      run: run, prompt: prompt,
      reasoning: "Clearer framing",
      suggested_template: "Improved prompt body",
      original_template: prompt.template
    )
  end

  describe "GET /completion_kit/suggestions/:id" do
    it "renders the suggestion show page anchored on the prompt by default" do
      get "/completion_kit/suggestions/#{suggestion.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Clearer framing")
      expect(response.body).to include("Improved prompt body")
      expect(response.body).to include("Back to prompt")
    end

    it "anchors breadcrumbs and back button on the run when from=run" do
      get "/completion_kit/suggestions/#{suggestion.id}?from=run"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Back to run")
      expect(response.body).to include(">Runs<")
    end

    it "404s when the suggestion does not exist" do
      expect { get "/completion_kit/suggestions/9999" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "POST /completion_kit/suggestions/:id/apply" do
    before { prompt.publish! }

    it "clones the prompt as a new published version and marks the suggestion applied" do
      expect { post "/completion_kit/suggestions/#{suggestion.id}/apply" }
        .to change(CompletionKit::Prompt, :count).by(1)

      new_prompt = CompletionKit::Prompt.order(:id).last
      expect(new_prompt.template).to eq("Improved prompt body")
      expect(new_prompt.published_at).to be_present
      expect(response).to redirect_to("/completion_kit/prompts/#{new_prompt.id}")
      expect(suggestion.reload.applied_at).to be_present
    end
  end
end
