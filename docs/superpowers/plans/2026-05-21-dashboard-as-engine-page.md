# Dashboard as a First-Class Engine Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the dashboard out of the standalone host app into the engine as a routed page, retire the standalone's separate onboarding, and re-home the concept tips onto the engine onboarding checklist. Resolves issue #41.

**Architecture:** A new `CompletionKit::DashboardController#show` renders the dashboard. A shared `workspace_ready?` helper on the engine `ApplicationController` drives a non-looping pair of redirects: onboarding sends ready workspaces to the dashboard, the dashboard sends not-ready workspaces to onboarding. The standalone app's root becomes a one-line redirect into the engine.

**Tech Stack:** Rails 8.1 engine (`isolate_namespace CompletionKit`), RSpec + FactoryBot, SimpleCov 100% line + branch coverage (CI-enforced).

**Context for the engineer:**
- The engine already ships `CompletionKit::DashboardStats`, the `DashboardDismissal` model + controller + routes, and the `completion_kit/dashboard/_worst_metric_card` / `_failures_card` / `completion_kit/runs/_table` partials. This plan adds the *page* that assembles them.
- The dashboard page currently lives only in the standalone app: `standalone/app/controllers/home_controller.rb#index` and `standalone/app/views/home/index.html.erb`.
- The engine enforces **100% line and branch coverage** via SimpleCov. Engine ERB views are tracked, so every branch in the new dashboard view needs a covering request spec. Standalone-app code is not covered (it has no test suite).
- Run the full suite from the repo root: `bundle exec rspec`. Expect `840 examples, 0 failures` before you start.
- The design spec is `docs/superpowers/specs/2026-05-21-dashboard-as-engine-page-design.md`.

**Project conventions (do not violate):**
- No code comments anywhere — Ruby, ERB, or CSS.
- No em dashes in copy.
- Commit messages: short subject line only, no body, no attribution lines.

**File structure:**
- `app/controllers/completion_kit/dashboard_controller.rb` — *new* — loads dashboard stats, gates on `workspace_ready?`.
- `app/views/completion_kit/dashboard/show.html.erb` — *new* — the dashboard page (moved from the standalone home view's set-up branch).
- `app/controllers/completion_kit/application_controller.rb` — *modified* — adds the `ONBOARDING_DISMISS_COOKIE` constant and `workspace_ready?`.
- `app/controllers/completion_kit/onboarding_controller.rb` — *modified* — uses the shared cookie constant; redirects to the dashboard instead of prompts.
- `config/routes.rb` — *modified* — adds the `dashboard` route.
- `app/views/layouts/completion_kit/application.html.erb` — *modified* — brand logo links to the dashboard.
- `app/services/completion_kit/onboarding/concepts.rb` — *new* — the concept definitions.
- `app/views/completion_kit/onboarding/_concept.html.erb` — *new* — the concept tip partial (moved from the standalone app).
- `app/views/completion_kit/onboarding/show.html.erb` — *modified* — renders a concept tip per checklist step.
- `standalone/app/controllers/home_controller.rb` — *modified* — `index` becomes a redirect.
- `standalone/app/views/home/index.html.erb`, `standalone/app/views/home/_concept.html.erb`, `standalone/app/helpers/home_helper.rb` — *deleted*.
- `spec/requests/completion_kit/dashboard_spec.rb` — *new*.
- `spec/requests/completion_kit/onboarding_spec.rb` — *modified* — redirect target is now the dashboard.

---

### Task 1: Engine dashboard page and landing gate

**Files:**
- Create: `app/controllers/completion_kit/dashboard_controller.rb`
- Create: `app/views/completion_kit/dashboard/show.html.erb`
- Create: `spec/requests/completion_kit/dashboard_spec.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/completion_kit/application_controller.rb`
- Modify: `app/controllers/completion_kit/onboarding_controller.rb`
- Modify: `app/views/layouts/completion_kit/application.html.erb`
- Modify: `spec/requests/completion_kit/onboarding_spec.rb`

- [ ] **Step 1: Add the dashboard route**

In `config/routes.rb`, add this line directly below `resources :dashboard_dismissals, only: [:create, :destroy]`:

```ruby
  get "dashboard", to: "dashboard#show", as: :dashboard
```

- [ ] **Step 2: Add the landing gate to `ApplicationController`**

Edit `app/controllers/completion_kit/application_controller.rb`. Add the constant directly below `layout "completion_kit/application"`:

```ruby
    ONBOARDING_DISMISS_COOKIE = :ck_onboarding_dismissed
```

And add this private method below `authenticate_completion_kit!` (inside the existing `private` section):

```ruby
    def workspace_ready?
      CompletionKit::Onboarding::Checklist.new.complete? ||
        cookies[ONBOARDING_DISMISS_COOKIE].present?
    end
```

- [ ] **Step 3: Point `OnboardingController` at the shared cookie constant and the dashboard**

Edit `app/controllers/completion_kit/onboarding_controller.rb`. Remove its own `DISMISS_COOKIE = :ck_onboarding_dismissed` line. Replace every `DISMISS_COOKIE` reference with `ONBOARDING_DISMISS_COOKIE` (inherited from `ApplicationController`). Change both redirect targets from `prompts_path` to `dashboard_path`. The file becomes:

```ruby
module CompletionKit
  class OnboardingController < ApplicationController
    def show
      cookies.delete(ONBOARDING_DISMISS_COOKIE) if params[:reset]
      @checklist = Onboarding::Checklist.new
      return if params[:reset]

      redirect_to dashboard_path if workspace_ready?
    end

    def dismiss
      cookies[ONBOARDING_DISMISS_COOKIE] = { value: "1", expires: 1.year.from_now, httponly: true }
      redirect_to dashboard_path, notice: "Setup skipped. Pick it back up from Settings → Getting started any time."
    end

    def sample_data
      Onboarding::SampleData.install!
      redirect_to onboarding_path, notice: "Loaded a sample dataset and prompt — edit or delete them whenever."
    end
  end
end
```

- [ ] **Step 4: Create `DashboardController`**

Create `app/controllers/completion_kit/dashboard_controller.rb`:

```ruby
module CompletionKit
  class DashboardController < ApplicationController
    def show
      return redirect_to(onboarding_path) unless workspace_ready?

      @prompt_count = Prompt.current_versions.count
      @run_count = Run.count
      @dataset_count = Dataset.count
      @metric_count = Metric.count
      @recent_runs = Run.order(created_at: :desc).limit(5)

      return unless @run_count > 5

      @activity = DashboardStats.activity
      @worst_metric = DashboardStats.worst_metric(since: 7.days.ago)
      @failures = DashboardStats.failures(since: 7.days.ago)
      @ignored_metrics = DashboardDismissal.metrics
      @ignored_failures = DashboardDismissal.failures
      @prompt_changes = DashboardStats.prompt_changes
    end
  end
end
```

- [ ] **Step 5: Create the dashboard view**

Create `app/views/completion_kit/dashboard/show.html.erb`. This is the set-up branch of the old standalone `home/index.html.erb` with two adjustments: route helpers lose the `completion_kit.` prefix (the view now lives inside the engine), and the em dashes in the empty-prompt-changes copy become commas. The `@recent_runs.any?` conditional stays — a workspace that dismissed onboarding without finishing setup is `workspace_ready?` yet can have zero runs.

```erb
<section class="ck-page-header">
  <div>
    <p class="ck-kicker">Dashboard</p>
    <h1 class="ck-title">Prompt Testing Lab</h1>
  </div>
  <div class="ck-actions">
    <%= link_to "New run →", new_run_path, class: "ck-button ck-button--secondary" %>
  </div>
</section>

<nav class="ck-statbar ck-rise" aria-label="Workspace totals">
  <%= link_to prompts_path, class: "ck-statbar__item" do %>
    <span class="ck-statbar__label">Prompts</span>
    <span class="ck-statbar__value"><%= @prompt_count %></span>
  <% end %>
  <%= link_to metrics_path, class: "ck-statbar__item" do %>
    <span class="ck-statbar__label">Metrics</span>
    <span class="ck-statbar__value"><%= @metric_count %></span>
  <% end %>
  <%= link_to datasets_path, class: "ck-statbar__item" do %>
    <span class="ck-statbar__label">Datasets</span>
    <span class="ck-statbar__value"><%= @dataset_count %></span>
  <% end %>
  <%= link_to runs_path, class: "ck-statbar__item" do %>
    <span class="ck-statbar__label">Runs</span>
    <span class="ck-statbar__value"><%= @run_count %></span>
  <% end %>
</nav>

<% if @activity %>
  <div class="ck-grid ck-grid--cards ck-grid--cards-3 ck-pulse-grid">
    <div class="ck-card ck-stat-card ck-rise" style="--rise-delay: 60ms;">
      <p class="ck-kicker">Activity · last 14 days</p>
      <% activity_max = @activity.map { |d| d[:count] }.max %>
      <div class="ck-sparkline" role="img" aria-label="<%= @activity.sum { |d| d[:count] } %> runs over the last 14 days">
        <% @activity.each do |day| %>
          <span class="ck-sparkline__bar<%= ' is-peak' if activity_max.to_i.positive? && day[:count] == activity_max %>"
                style="height: <%= activity_max.to_i.zero? ? 0 : (day[:count] * 100.0 / activity_max).round %>%"
                title="<%= day[:date].strftime('%b %-d') %>: <%= day[:count] %> run<%= 's' unless day[:count] == 1 %>"></span>
        <% end %>
      </div>
      <p class="ck-stat-card__foot">
        <span class="ck-stat-card__figure"><%= @activity.sum { |d| d[:count] } %></span> runs in the window
      </p>
    </div>

    <%= render "completion_kit/dashboard/worst_metric_card",
               worst_metric: @worst_metric, ignored_metrics: @ignored_metrics %>

    <%= render "completion_kit/dashboard/failures_card",
               failures: @failures, ignored_failures: @ignored_failures %>
  </div>

  <div class="ck-card ck-card--spaced ck-rise" style="--rise-delay: 240ms;">
    <p class="ck-kicker">Prompt changes · version over version</p>
    <% if @prompt_changes.any? %>
      <ul class="ck-improvements">
        <% @prompt_changes.each do |row| %>
          <% gained = row[:delta].positive? %>
          <li class="ck-improvement">
            <%= link_to row[:prompt].name, prompt_path(row[:prompt]), class: "ck-improvement__name ck-link" %>
            <span class="ck-improvement__versions">v<%= row[:from_version] %> &rarr; v<%= row[:to_version] %></span>
            <span class="ck-improvement__scores">
              <span class="ck-improvement__from"><%= row[:from_score] %></span>
              <span class="ck-improvement__arrow">&rarr;</span>
              <span class="ck-improvement__to"><%= row[:to_score] %></span>
            </span>
            <span class="ck-improvement__delta <%= gained ? 'is-gain' : 'is-loss' %>"><%= gained ? '▲' : '▼' %> <%= '%+.2f' % row[:delta] %></span>
          </li>
        <% end %>
      </ul>
    <% else %>
      <p class="ck-improvements__empty">
        No measured changes yet. Edit a prompt to create a new version, re-run it against the same dataset and metrics, and the score change, up or down, shows up here.
      </p>
    <% end %>
  </div>
<% end %>

<section class="ck-card--spaced">
  <div class="ck-split">
    <h2 class="ck-section-title">Recent runs</h2>
    <%= link_to "View all", runs_path, class: "ck-link" %>
  </div>

  <% if @recent_runs.any? %>
    <%= render "completion_kit/runs/table", runs: @recent_runs %>
  <% else %>
    <div class="ck-empty">No runs yet.&ensp;<%= link_to "Create your first run →", new_run_path, class: "ck-link" %></div>
  <% end %>
</section>
```

- [ ] **Step 6: Point the engine brand logo at the dashboard**

In `app/views/layouts/completion_kit/application.html.erb`, the `.ck-brand` link currently reads:

```erb
      <%= link_to (main_app.respond_to?(:root_path) ? main_app.root_path : prompts_path), class: "ck-brand" do %>
```

Change the target to `dashboard_path`:

```erb
      <%= link_to dashboard_path, class: "ck-brand" do %>
```

- [ ] **Step 7: Update the onboarding request spec for the new redirect target**

Edit `spec/requests/completion_kit/onboarding_spec.rb`. Replace the `prompts_path` let with a `dashboard_path` let and update the three redirect expectations. Specifically:

- Line 4: change `let(:prompts_path) { "/completion_kit/prompts" }` to `let(:dashboard_path) { "/completion_kit/dashboard" }`.
- In "redirects to prompts once every setup step is complete" (rename to "redirects to the dashboard once every setup step is complete"): `expect(response).to redirect_to(dashboard_path)`.
- In "redirects to prompts when onboarding has been dismissed" (rename to "redirects to the dashboard when onboarding has been dismissed"): `expect(response).to redirect_to(dashboard_path)`.
- In the `POST /onboarding/dismiss` example: change `expect(response).to redirect_to(prompts_path)` to `redirect_to(dashboard_path)`, and the final `get "/completion_kit/"` expectation to `redirect_to(dashboard_path)`.

- [ ] **Step 8: Write the dashboard request spec**

Create `spec/requests/completion_kit/dashboard_spec.rb`. The dashboard renders only for a "ready" workspace, so every render-path example first creates one of each record. The `DashboardStats` aggregate methods are stubbed so the view's branches can be exercised deterministically; `DashboardStats` itself is covered by its own spec.

```ruby
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
      expect(response).to redirect_to("/completion_kit/")
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
```

Coverage note: example 1 covers the not-ready redirect. Example 2 (ready via runs) covers the `if @activity` false branch and the `@recent_runs.any?` true branch. Example 3 (ready via the dismiss cookie, zero runs) covers the `@recent_runs.any?` false branch ("No runs yet"). The activity example exercises `activity_max.positive?` true plus a day at peak (count 3), a non-peak day, a single-run day (count 1, the `unless day[:count] == 1` false branch) and a multi-run day (the true branch), plus the `@prompt_changes.any?` true branch and `is-gain`. The regression example covers `is-loss`. The all-zero example covers `activity_max.zero?` true (so `is-peak` is never emitted) and the `@prompt_changes.any?` false branch.

- [ ] **Step 9: Run the suite**

Run: `bundle exec rspec`
Expected: all examples pass, `Line Coverage: 100.0%`, `Branch Coverage: 100.0%`. If a branch in `dashboard/show.html.erb` is uncovered, SimpleCov names the file and line; add a covering scenario in the dashboard spec.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/completion_kit/dashboard_controller.rb app/views/completion_kit/dashboard/show.html.erb spec/requests/completion_kit/dashboard_spec.rb config/routes.rb app/controllers/completion_kit/application_controller.rb app/controllers/completion_kit/onboarding_controller.rb app/views/layouts/completion_kit/application.html.erb spec/requests/completion_kit/onboarding_spec.rb
git commit -m "ship the dashboard as a first-class engine page"
```

---

### Task 2: Concept tips on the engine onboarding

**Files:**
- Create: `app/services/completion_kit/onboarding/concepts.rb`
- Create: `app/views/completion_kit/onboarding/_concept.html.erb`
- Modify: `app/views/completion_kit/onboarding/show.html.erb`
- Modify: `spec/requests/completion_kit/onboarding_spec.rb`

- [ ] **Step 1: Create the concept definitions**

Create `app/services/completion_kit/onboarding/concepts.rb`. The hash is keyed to match the `Onboarding::Checklist` step keys (`credential`, `dataset`, `prompt`, `run`) so the view can index it with `step.key` directly. `response` and `metric` are kept for reuse.

```ruby
module CompletionKit
  module Onboarding
    module Concepts
      DEFINITIONS = {
        credential: {
          name: "Provider Credential",
          definition: "An API key for a model provider such as OpenAI or Anthropic. Encrypted at rest and never returned through the API."
        },
        dataset: {
          name: "Dataset",
          definition: "A CSV of real inputs. Each row becomes one test case."
        },
        prompt: {
          name: "Prompt",
          definition: "A versioned template with {{variable}} placeholders. Editing a prompt that has already been run creates a new version, so past results stay reproducible."
        },
        run: {
          name: "Run",
          definition: "One execution of a prompt against a dataset. Stores every output and the judge's scores."
        },
        response: {
          name: "Response",
          definition: "The model's output for a single dataset row, with the judge's reviews attached."
        },
        metric: {
          name: "Metric",
          definition: "An evaluation dimension with its own 1-5 rubric. The LLM judge scores every response against it."
        }
      }.freeze
    end
  end
end
```

- [ ] **Step 2: Create the concept tip partial**

Create `app/views/completion_kit/onboarding/_concept.html.erb`. It is the standalone partial moved into the engine: the `CONCEPTS` lookup now points at `Onboarding::Concepts::DEFINITIONS`, and `term` is optional (it defaults to an empty string, since the onboarding usage shows just the icon).

```erb
<% concept = CompletionKit::Onboarding::Concepts::DEFINITIONS.fetch(key) -%>
<% term = local_assigns.fetch(:term, "") -%>
<span class="ck-concept"><%= term %><button type="button" class="ck-concept__toggle" aria-label="What is a <%= concept[:name] %>?" aria-describedby="concept-<%= key %>-pop"><%= heroicon_tag "information-circle", variant: :outline, size: 14, class: "ck-concept__icon", "aria-hidden": "true" %></button><span class="ck-concept__pop" role="tooltip" id="concept-<%= key %>-pop"><span class="ck-concept__name"><%= concept[:name] %></span><span class="ck-concept__body"><%= concept[:definition] %></span></span></span>
```

- [ ] **Step 3: Render a concept tip beside each checklist step title**

In `app/views/completion_kit/onboarding/show.html.erb`, the step title block currently reads:

```erb
                <h3 class="ck-launch__step-title">
                  <% if step.done? %>
                    <%= step.title %>
                  <% else %>
                    <%= link_to step.title, step_path %>
                  <% end %>
                </h3>
```

Add the concept tip after the conditional, still inside the `<h3>`:

```erb
                <h3 class="ck-launch__step-title">
                  <% if step.done? %>
                    <%= step.title %>
                  <% else %>
                    <%= link_to step.title, step_path %>
                  <% end %>
                  <%= render "concept", key: step.key %>
                </h3>
```

Each `Onboarding::Checklist` step has a `key` of `:credential`, `:dataset`, `:prompt`, or `:run`, each of which is a key in `Concepts::DEFINITIONS`.

- [ ] **Step 4: Add a coverage assertion to the onboarding spec**

In `spec/requests/completion_kit/onboarding_spec.rb`, add this example inside the `describe "GET /onboarding?reset=1"` block:

```ruby
    it "shows a concept tip on each checklist step" do
      get "/completion_kit/onboarding?reset=1"

      expect(response.body).to include('id="concept-credential-pop"')
      expect(response.body).to include("Provider Credential")
      expect(response.body).to include('id="concept-run-pop"')
    end
```

- [ ] **Step 5: Run the suite**

Run: `bundle exec rspec spec/requests/completion_kit/onboarding_spec.rb`
Expected: all examples pass. Then run the full `bundle exec rspec` and confirm `Line Coverage: 100.0%`, `Branch Coverage: 100.0%`. The four checklist steps render four tips, so all four `DEFINITIONS` keys used by onboarding are exercised.

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/onboarding/concepts.rb app/views/completion_kit/onboarding/_concept.html.erb app/views/completion_kit/onboarding/show.html.erb spec/requests/completion_kit/onboarding_spec.rb
git commit -m "show concept tips on the onboarding checklist"
```

---

### Task 3: Shrink the standalone app

**Files:**
- Modify: `standalone/app/controllers/home_controller.rb`
- Delete: `standalone/app/views/home/index.html.erb`
- Delete: `standalone/app/views/home/_concept.html.erb`
- Delete: `standalone/app/helpers/home_helper.rb`

- [ ] **Step 1: Reduce `HomeController` to a redirect**

Replace the entire contents of `standalone/app/controllers/home_controller.rb` with:

```ruby
class HomeController < ActionController::Base
  before_action :authenticate!

  def index
    redirect_to completion_kit.dashboard_path
  end

  private

  def authenticate!
    cfg = CompletionKit.config
    return unless cfg.username && cfg.password
    return if session[:authenticated]

    redirect_to login_path
  end
end
```

The `helper CompletionKit::ApplicationHelper` and `layout "application"` lines are dropped: `index` only redirects, so it renders no view. The `authenticate!` filter is unchanged, so an unauthenticated visitor still goes to the login page first.

- [ ] **Step 2: Delete the standalone dashboard and concept-tip files**

```bash
git rm standalone/app/views/home/index.html.erb \
       standalone/app/views/home/_concept.html.erb \
       standalone/app/helpers/home_helper.rb
```

- [ ] **Step 3: Verify the engine suite still passes**

Run: `bundle exec rspec`
Expected: `Line Coverage: 100.0%`, `Branch Coverage: 100.0%`, all examples pass. This task changes only standalone-app code, which the engine suite does not cover, so the result must be identical to before.

- [ ] **Step 4: Smoke-test the standalone redirect manually**

The standalone app has no automated tests. Stop any server on port 3000, then back up the seeded dev database, start fresh, and check the redirect chain:

```bash
cd standalone
mkdir -p tmp/db-backup
mv db/development.sqlite3* tmp/db-backup/
DISABLE_SPRING=1 bin/rails db:prepare
DISABLE_SPRING=1 bin/rails server
```

Visit `http://localhost:3000/`. Expected: it redirects to `/completion_kit/dashboard`, which (an empty workspace is not ready) redirects on to `/completion_kit/` and renders the onboarding checklist with concept-tip icons on the step titles. Stop the server, then restore the seeded database:

```bash
cd standalone
rm -f db/development.sqlite3*
mv tmp/db-backup/* db/
rmdir tmp/db-backup
```

With the seeded database, `http://localhost:3000/` should redirect through to `/completion_kit/dashboard` and render the dashboard.

- [ ] **Step 5: Commit**

```bash
git add standalone/app/controllers/home_controller.rb
git commit -m "redirect the standalone root into the engine dashboard"
```

---

## Notes for the executor

- Tasks 1 and 2 are independent and may run in either order. Task 3 depends only on Task 1 (it redirects to `completion_kit.dashboard_path`, which Task 1 routes). Task 3 deletes the standalone `home/index.html.erb`, `_concept.html.erb`, and `home_helper.rb` together; those three are only referenced by each other, so the deletion is self-contained and does not depend on Task 2's separate engine concept partial.
- The `worst_metric_card` and `failures_card` partials are unchanged and already covered by `spec/requests/completion_kit/dashboard_dismissals_spec.rb`; do not modify them.
- Do not change `DashboardStats`, the `@run_count > 5` threshold, or the dashboard's visual design.
