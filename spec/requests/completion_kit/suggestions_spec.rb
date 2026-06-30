require "rails_helper"

RSpec.describe "CompletionKit suggestions", type: :request do
  let(:prompt) { create(:completion_kit_prompt, name: "Static", template: "Static prompt") }
  let(:run) { create(:completion_kit_run, prompt: prompt) }
  let(:suggestion) do
    CompletionKit::Suggestion.create!(
      run: run, prompt: prompt,
      reasoning: "Clearer framing",
      suggested_template: "Improved prompt body",
      original_template: prompt.template,
      status: "ready"
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

    it "shows a check pass-rate badge in the header when the run has resolved checks" do
      check = create(:completion_kit_metric, :check)
      run.replace_metrics!([check.id])
      resp = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: resp, metric: check, passed: true)

      get "/completion_kit/suggestions/#{suggestion.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("100%")
    end

    it "anchors breadcrumbs and back button on the run when from=run" do
      get "/completion_kit/suggestions/#{suggestion.id}?from=run"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Back to run")
      expect(response.body).to include(">Runs<")
    end

    it "subscribes to the suggestion stream and shows a validating state while pending" do
      pending = CompletionKit::Suggestion.create!(
        run: run, prompt: prompt, original_template: prompt.template, status: "pending"
      )

      get "/completion_kit/suggestions/#{pending.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-cable-stream-source")
      expect(response.body).to include("Validating")
    end

    it "shows a try-again state when the suggestion failed" do
      failed = CompletionKit::Suggestion.create!(
        run: run, prompt: prompt, original_template: prompt.template, status: "failed"
      )

      get "/completion_kit/suggestions/#{failed.id}?from=run"
      expect(response.body).to include("validated rewrite")
      expect(response.body).to include("Try again")
    end

    it "renders the held-out scoreboard when a validation summary is present" do
      suggestion.update!(validation_summary: {
        "before_avg" => 3.0, "after_avg" => 4.0, "improved" => 2,
        "regressed" => 0, "unchanged" => 1, "tested" => 3, "capped" => false
      })

      get "/completion_kit/suggestions/#{suggestion.id}"
      expect(response.body).to include("held-out response")
      expect(response.body).to include("Apply suggestion")
    end

    it "gates publish when the rewrite couldn't be re-scored at all" do
      suggestion.update!(validation_summary: { "tested" => 0, "capped" => false, "after_avg" => nil, "before_avg" => nil })

      get "/completion_kit/suggestions/#{suggestion.id}"
      expect(response.body).to include("Couldn't re-score")
      expect(response.body).to include("Apply anyway")
      expect(response.body).to include("be re-scored against the run")
    end

    it "gates publish behind a confirmation when the rewrite scored net negative" do
      suggestion.update!(validation_summary: {
        "before_avg" => 4.0, "after_avg" => 3.0, "improved" => 0,
        "regressed" => 2, "unchanged" => 1, "tested" => 3, "capped" => false
      })

      get "/completion_kit/suggestions/#{suggestion.id}"
      expect(response.body).to include("Apply anyway")
      expect(response.body).to include("scored lower than the original")
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

    it "does not re-apply a suggestion that is already applied" do
      suggestion.update!(applied_at: Time.current)

      expect { post "/completion_kit/suggestions/#{suggestion.id}/apply" }
        .not_to change(CompletionKit::Prompt, :count)
      expect(response).to redirect_to("/completion_kit/suggestions/#{suggestion.id}")
      expect(flash[:notice]).to include("already applied")
    end

    it "refuses to apply a suggestion that is still pending" do
      pending = CompletionKit::Suggestion.create!(
        run: run, prompt: prompt, original_template: prompt.template, status: "pending"
      )

      expect { post "/completion_kit/suggestions/#{pending.id}/apply" }
        .not_to change(CompletionKit::Prompt, :count)
      expect(response).to redirect_to("/completion_kit/suggestions/#{pending.id}")
      expect(flash[:alert]).to include("isn't ready")
    end
  end
end
