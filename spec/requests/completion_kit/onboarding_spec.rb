require "rails_helper"

RSpec.describe "CompletionKit onboarding", type: :request do
  let(:prompts_path) { "/completion_kit/prompts" }

  def complete_setup!
    create(:completion_kit_provider_credential)
    dataset = create(:completion_kit_dataset)
    prompt = create(:completion_kit_prompt)
    create(:completion_kit_run, prompt: prompt, dataset: dataset)
  end

  describe "GET / (root)" do
    it "renders the setup checklist on a fresh install" do
      get "/completion_kit/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setting up")
      expect(response.body).to include("Connect a provider")
      expect(response.body).to include("Upload a dataset")
      expect(response.body).to include("Next up")
      expect(response.body).to include("0 of 4 done")
    end

    it "redirects to prompts once every setup step is complete" do
      complete_setup!

      get "/completion_kit/"
      expect(response).to redirect_to(prompts_path)
    end

    it "redirects to prompts when onboarding has been dismissed" do
      cookies[:ck_onboarding_dismissed] = "1"

      get "/completion_kit/"
      expect(response).to redirect_to(prompts_path)
    end
  end

  describe "GET /onboarding?reset=1" do
    it "re-shows the checklist even when dismissed, and clears the dismiss cookie" do
      cookies[:ck_onboarding_dismissed] = "1"

      get "/completion_kit/onboarding?reset=1"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setting up")
      expect(response.cookies["ck_onboarding_dismissed"]).to be_blank
    end

    it "shows done / next / pending step states together for a partial setup" do
      create(:completion_kit_provider_credential)

      get "/completion_kit/onboarding?reset=1"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ck-launch__step--done")
      expect(response.body).to include("ck-launch__step--next")
      expect(response.body).to include("ck-launch__step--pending")
      expect(response.body).to include("1 of 4 done")
    end

    it "shows the all-set panel when everything is complete" do
      complete_setup!

      get "/completion_kit/onboarding?reset=1"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("all set up")
      expect(response.body).to include("ck-launch__quicklink")
    end
  end

  describe "POST /onboarding/dismiss" do
    it "sets the dismiss cookie, redirects to prompts with a notice, and stays dismissed" do
      post "/completion_kit/onboarding/dismiss"

      expect(response).to redirect_to(prompts_path)
      expect(response.cookies["ck_onboarding_dismissed"]).to eq("1")

      follow_redirect!
      expect(response.body).to include("Setup skipped")

      get "/completion_kit/"
      expect(response).to redirect_to(prompts_path)
    end
  end
end
