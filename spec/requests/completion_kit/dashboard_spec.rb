require "rails_helper"

RSpec.describe "CompletionKit dashboard", type: :request do
  let(:dashboard) { "/completion_kit/dashboard" }

  def ready_workspace!(run_count: 1)
    create(:completion_kit_provider_credential)
    dataset = create(:completion_kit_dataset)
    prompt = create(:completion_kit_prompt)
    create_list(:completion_kit_run, run_count, prompt: prompt, dataset: dataset)
  end

  def stub_pulse_cards!
    allow(CompletionKit::DashboardStats).to receive(:activity).and_return([{ date: Date.new(2026, 5, 3), count: 1 }])
    allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
    allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
    allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return([])
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
      expect(response.body).not_to include("Activity · 14D")
    end

    it "renders the no-runs state when onboarding was dismissed before any run exists" do
      cookies[:ck_onboarding_dismissed] = "1"

      get dashboard

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No runs yet")
      expect(response.body).not_to include("Activity · 14D")
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
      expect(response.body).to include("Activity · 14D")
      expect(response.body).to include("is-peak")
      expect(response.body).to include("Prompt changes")
      expect(response.body).to include("is-gain")
    end

    it "drops the checks card and narrows the grid when the workspace has no check metrics" do
      ready_workspace!(run_count: 6)
      stub_pulse_cards!

      get dashboard

      expect(response.body).to include("ck-grid--cards-3")
      expect(response.body).not_to include("ck-failing-checks-card")
    end

    it "leads the checks card with a pass rate and names the run behind each failure" do
      ready_workspace!(run_count: 6)
      run = CompletionKit::Run.first
      check = create(:completion_kit_metric, :check, name: "Valid JSON")
      3.times do
        row = create(:completion_kit_response, run: run)
        create(:completion_kit_review, :check, response: row, metric: check, metric_name: "Valid JSON", passed: false)
      end
      passing_row = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: passing_row, metric: check, metric_name: "Valid JSON", passed: true)
      stub_pulse_cards!

      get dashboard

      expect(response.body).to include("ck-grid--cards-4")
      expect(response.body).to include("Checks · 14D")
      expect(response.body).to include("25%")
      expect(response.body).to include("is-low")
      expect(response.body).to include("ck-sparkline__bar is-low")
      expect(response.body).to include("Failed in #{run.name}")
      expect(response.body).to include("1 more failing")
    end

    it "reads as all-clear when every resolved check passed" do
      ready_workspace!(run_count: 6)
      run = CompletionKit::Run.first
      check = create(:completion_kit_metric, :check, name: "Valid JSON")
      row = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: row, metric: check, metric_name: "Valid JSON", passed: true)
      stub_pulse_cards!

      get dashboard

      expect(response.body).to include("100%")
      expect(response.body).to include("is-high")
      expect(response.body).not_to include("ck-sparkline__bar is-low")
      expect(response.body).not_to include("ck-sparkline__bar is-medium")
      expect(response.body).to include("Every check passed in the window")
    end

    it "invites the first check run when a check metric exists but nothing has resolved" do
      ready_workspace!(run_count: 6)
      create(:completion_kit_metric, :check, name: "Valid JSON")
      stub_pulse_cards!

      get dashboard

      expect(response.body).to include("Not run yet")
      expect(response.body).to include("Add a check metric to a run to populate this")
    end

    it "counts a single failing check without the overflow line" do
      ready_workspace!(run_count: 6)
      run = CompletionKit::Run.first
      check = create(:completion_kit_metric, :check, name: "Valid JSON")
      row = create(:completion_kit_response, run: run)
      create(:completion_kit_review, :check, response: row, metric: check, metric_name: "Valid JSON", passed: false)
      stub_pulse_cards!

      get dashboard

      expect(response.body).to include("1 check failing in the window")
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

    it "shows a hidden-runs message, not the new-user CTA, when every run is hidden on the dashboard" do
      cookies[:ck_onboarding_dismissed] = "1"
      prompt = create(:completion_kit_prompt)
      dataset = create(:completion_kit_dataset)
      create(:completion_kit_run, prompt: prompt, dataset: dataset, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      get dashboard

      expect(response.body).not_to include("Create your first run")
      expect(response.body).to include("Your older runs are hidden")
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "filters the recent-runs list through a host-configured runs_display_scope" do
      cookies[:ck_onboarding_dismissed] = "1"
      prompt = create(:completion_kit_prompt)
      dataset = create(:completion_kit_dataset)
      create(:completion_kit_run, prompt: prompt, dataset: dataset, name: "Dashboard Recent")
      create(:completion_kit_run, prompt: prompt, dataset: dataset, name: "Dashboard Old", created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      get dashboard

      expect(response.body).to include("Dashboard Recent")
      expect(response.body).not_to include("Dashboard Old")
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "passes the shown (post-scope) recent runs to the host runs_display_footer_partial" do
      cookies[:ck_onboarding_dismissed] = "1"
      prompt = create(:completion_kit_prompt)
      dataset = create(:completion_kit_dataset)
      create_list(:completion_kit_run, 2, prompt: prompt, dataset: dataset)
      create(:completion_kit_run, prompt: prompt, dataset: dataset, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
      CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

      get dashboard

      expect(response.body).to include("spec-host-runs-footer: 2 runs in view")
    ensure
      CompletionKit.config.runs_display_footer_partial = nil
      CompletionKit.config.runs_display_scope = nil
    end

    it "shows the display-scoped run count on the Runs stat card" do
      cookies[:ck_onboarding_dismissed] = "1"
      prompt = create(:completion_kit_prompt)
      dataset = create(:completion_kit_dataset)
      create_list(:completion_kit_run, 6, prompt: prompt, dataset: dataset, created_at: 90.days.ago)
      create_list(:completion_kit_run, 2, prompt: prompt, dataset: dataset)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
      allow(CompletionKit::DashboardStats).to receive(:activity).and_return([{ date: Date.new(2026, 5, 3), count: 1 }])
      allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
      allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
      allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return([])

      get dashboard

      expect(response.body).to include('<span class="ck-statbar__value">2</span>')
      expect(response.body).not_to include('<span class="ck-statbar__value">8</span>')
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "keeps the stat cards gated on the unscoped run total when retention hides most runs" do
      cookies[:ck_onboarding_dismissed] = "1"
      prompt = create(:completion_kit_prompt)
      dataset = create(:completion_kit_dataset)
      create_list(:completion_kit_run, 6, prompt: prompt, dataset: dataset, created_at: 90.days.ago)
      create_list(:completion_kit_run, 2, prompt: prompt, dataset: dataset)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
      allow(CompletionKit::DashboardStats).to receive(:activity).and_return([{ date: Date.new(2026, 5, 3), count: 1 }])
      allow(CompletionKit::DashboardStats).to receive(:worst_metric).and_return(nil)
      allow(CompletionKit::DashboardStats).to receive(:failures).and_return(count: 0, items: [])
      allow(CompletionKit::DashboardStats).to receive(:prompt_changes).and_return([])

      get dashboard

      expect(response.body).to include("Activity · 14D")
    ensure
      CompletionKit.config.runs_display_scope = nil
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
      expect(response.body).to include("Activity · 14D")
      expect(response.body).not_to include("is-peak")
      expect(response.body).to include("No measured changes yet")
    end
  end
  describe "prompts served card" do
    it "shows an honest empty state before anything has been fetched" do
      ready_workspace!

      get "/completion_kit/dashboard"

      expect(response.body).to include("Prompts served")
      expect(response.body).to include("No prompts fetched in the last 7 days")
    end

    it "lists the most-fetched prompts without needing any runs to exist" do
      ready_workspace!
      prompt = create(:completion_kit_prompt, name: "Hot Prompt")
      CompletionKit::PromptServe.create!(prompt_id: prompt.id, family_key: prompt.family_key,
                                        served_on: Date.current, serve_count: 17, last_served_at: Time.current)

      get "/completion_kit/dashboard"

      expect(response.body).to include("Hot Prompt")
      expect(response.body).to include("17")
      expect(response.body).not_to include("No prompts fetched in the last 7 days")
    end
  end
end
