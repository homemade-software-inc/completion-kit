require "rails_helper"

RSpec.describe "CompletionKit dashboard", type: :request do
  let(:dashboard) { "/completion_kit/dashboard" }

  def ready_workspace!(run_count: 1)
    create(:completion_kit_provider_credential)
    dataset = create(:completion_kit_dataset)
    prompt = create(:completion_kit_prompt)
    create_list(:completion_kit_run, run_count, prompt: prompt, dataset: dataset)
  end

  describe "GET /completion_kit/dashboard" do
    it "redirects an unconfigured workspace to onboarding" do
      get dashboard
      expect(response).to redirect_to("/completion_kit/onboarding")
    end

    it "renders the dashboard with five or fewer runs and no activity grid" do
      ready_workspace!(run_count: 2)

      get dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Prompt Testing Lab")
      expect(response.body).to include("Workspace totals")
      expect(response.body).to include("Recent runs")
      expect(response.body).not_to include("Activity · last 14 days")
    end

    it "renders the no-runs state when onboarding was dismissed before any run exists" do
      cookies[:ck_onboarding_dismissed] = "1"

      get dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No runs yet")
      expect(response.body).not_to include("Activity · last 14 days")
    end

    it "renders the activity grid and a populated prompt-changes list when more than five runs exist" do
      ready_workspace!(run_count: 6)
      prompt = CompletionKit::Prompt.first
      allow(CompletionKit::DashboardStats).to receive(:activity).and_return(
        [
          { date: Date.new(2026, 5, 1), count: 0 },
          { date: Date.new(2026, 5, 2), count: 1 },
          { date: Date.new(2026, 5, 3), count: 3 }
        ]
      )
      allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
      allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
      allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return(
        [{ prompt: prompt, from_version: 1, to_version: 2, from_score: 4.2, to_score: 4.8, delta: 0.6 }]
      )

      get dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Activity · last 14 days")
      expect(response.body).to include("is-peak")
      expect(response.body).to include("Prompt changes")
      expect(response.body).to include("is-gain")
    end

    it "renders a regression row in prompt changes" do
      ready_workspace!(run_count: 6)
      prompt = CompletionKit::Prompt.first
      allow(CompletionKit::DashboardStats).to receive(:activity).and_return(
        [{ date: Date.new(2026, 5, 3), count: 1 }]
      )
      allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
      allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
      allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return(
        [{ prompt: prompt, from_version: 2, to_version: 3, from_score: 4.8, to_score: 4.2, delta: -0.6 }]
      )

      get dashboard

      expect(response.body).to include("is-loss")
    end

    it "renders an all-zero sparkline and the empty prompt-changes state" do
      ready_workspace!(run_count: 6)
      allow(CompletionKit::DashboardStats).to receive(:activity).and_return(
        [
          { date: Date.new(2026, 5, 1), count: 0 },
          { date: Date.new(2026, 5, 2), count: 0 }
        ]
      )
      allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
      allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
      allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return([])

      get dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Activity · last 14 days")
      expect(response.body).not_to include("is-peak")
      expect(response.body).to include("No measured changes yet")
    end
  end
end
