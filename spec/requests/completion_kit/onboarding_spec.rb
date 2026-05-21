require "rails_helper"

RSpec.describe "CompletionKit onboarding", type: :request do
  let(:dashboard_path) { "/completion_kit/dashboard" }

  def complete_setup!
    create(:completion_kit_provider_credential)
    dataset = create(:completion_kit_dataset)
    prompt = create(:completion_kit_prompt)
    create(:completion_kit_run, prompt: prompt, dataset: dataset)
  end

  describe "GET / (root)" do
    it "renders the setup checklist on a fresh install, including the Load sample data button" do
      get "/completion_kit/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Finish setting up")
      expect(response.body).to include("Connect a provider")
      expect(response.body).to include("Upload a dataset")
      expect(response.body).to include("Next up")
      expect(response.body).to include("0 of 4 done")
      expect(response.body).to include("Load sample data")
    end

    it "hides the Load sample data button once a dataset or prompt exists" do
      create(:completion_kit_prompt)

      get "/completion_kit/onboarding?reset=1"
      expect(response.body).not_to include("Load sample data")
    end

    it "redirects to the dashboard once every setup step is complete" do
      complete_setup!

      get "/completion_kit/"
      expect(response).to redirect_to(dashboard_path)
    end

    it "redirects to the dashboard when onboarding has been dismissed" do
      cookies[:ck_onboarding_dismissed] = "1"

      get "/completion_kit/"
      expect(response).to redirect_to(dashboard_path)
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
    it "sets the dismiss cookie, redirects to the dashboard with a notice, and stays dismissed" do
      post "/completion_kit/onboarding/dismiss"

      expect(response).to redirect_to(dashboard_path)
      expect(response.cookies["ck_onboarding_dismissed"]).to eq("1")

      follow_redirect!
      expect(response.body).to include("Setup skipped")

      get "/completion_kit/"
      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /onboarding/sample-data" do
    it "loads the canned dataset + prompt and returns to the onboarding checklist with a notice" do
      expect { post "/completion_kit/onboarding/sample-data" }
        .to change(CompletionKit::Dataset, :count).by(1)
        .and change(CompletionKit::Prompt, :count).by(1)

      expect(response).to redirect_to("/completion_kit/onboarding")
      follow_redirect!
      expect(response.body).to include("Loaded a sample dataset and prompt")
      expect(response.body).to include("2 of 4 done")
      expect(response.body).not_to include("Load sample data")
    end

    it "is a no-op when a dataset or prompt already exists" do
      create(:completion_kit_dataset)

      expect { post "/completion_kit/onboarding/sample-data" }
        .to change(CompletionKit::Dataset, :count).by(0)
        .and change(CompletionKit::Prompt, :count).by(0)
      expect(response).to redirect_to("/completion_kit/onboarding")
    end
  end
end
