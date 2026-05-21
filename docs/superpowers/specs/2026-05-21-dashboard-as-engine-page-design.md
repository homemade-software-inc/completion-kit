# Dashboard as a first-class engine page — design

## Goal

Move the dashboard page out of the standalone host app and into the engine, so
every host (the bundled standalone app and completion-kit-cloud) gets the
assembled dashboard by mounting the engine, not by cloning a page. Retire the
standalone app's separate onboarding state and consolidate on the engine's
onboarding checklist.

Resolves issue #41.

## Background

The engine already ships the dashboard's parts: `CompletionKit::DashboardStats`,
the `DashboardDismissal` model + `DashboardDismissalsController` + routes, the
`completion_kit/dashboard/_worst_metric_card` and `_failures_card` partials, and
`completion_kit/runs/_table`. It does not ship the assembled dashboard page.

The dashboard page exists only in the standalone app: `HomeController#index`
(stat loading) and `home/index.html.erb` (the view). That view has two branches:
a set-up branch (the dashboard) and a not-set-up branch (three getting-started
cards, which carry the concept tips added in 0.5.30).

The engine also already has its own onboarding: `OnboardingController#show`
renders `Onboarding::Checklist` (a four-step checklist: provider, dataset,
prompt, run) with a progress indicator and a sample-data action. So the
standalone app's three getting-started cards and the engine's onboarding
checklist are two overlapping getting-started UIs.

## Decisions

- The standalone app's not-set-up state is retired. Everything uses the engine's
  `onboarding#show` checklist.
- The standalone app's root redirects into the engine. It renders nothing
  itself.
- The 0.5.30 concept tips move into the engine and re-home onto the onboarding
  checklist.

## Components

### 1. `CompletionKit::DashboardController#show` (new, engine)

`app/controllers/completion_kit/dashboard_controller.rb`. The action:

1. `redirect_to onboarding_path and return unless workspace_ready?`
2. Otherwise load the dashboard data, lifted verbatim from the current
   standalone `HomeController#index`:
   - `@prompt_count = Prompt.current_versions.count`
   - `@run_count = Run.count`
   - `@dataset_count = Dataset.count`
   - `@metric_count = Metric.count`
   - `@recent_runs = Run.order(created_at: :desc).limit(5)`
   - When `@run_count > 5`: `@activity = DashboardStats.activity`,
     `@worst_metric = DashboardStats.worst_metric(since: 7.days.ago)`,
     `@failures = DashboardStats.failures(since: 7.days.ago)`,
     `@ignored_metrics = DashboardDismissal.metrics`,
     `@ignored_failures = DashboardDismissal.failures`,
     `@prompt_changes = DashboardStats.prompt_changes`.

### 2. Route (engine)

`config/routes.rb`: `get "dashboard", to: "dashboard#show", as: :dashboard`.

### 3. `app/views/completion_kit/dashboard/show.html.erb` (new, engine)

The set-up branch of the current standalone `home/index.html.erb`: the
`ck-page-header` ("Dashboard" kicker, "Prompt Testing Lab" title, New run
button), the `ck-statbar`, the `@activity` card grid (sparkline + the
`worst_metric_card` and `failures_card` partials), the prompt-changes card, and
the recent-runs section. Partial paths stay `completion_kit/...` and resolve
the same from inside the engine. The not-set-up branch is not carried over.

### 4. Landing gate (engine)

In `CompletionKit::ApplicationController`, a private method:

```ruby
ONBOARDING_DISMISS_COOKIE = :ck_onboarding_dismissed

def workspace_ready?
  CompletionKit::Onboarding::Checklist.new.complete? ||
    cookies[ONBOARDING_DISMISS_COOKIE].present?
end
```

`OnboardingController` currently defines `DISMISS_COOKIE = :ck_onboarding_dismissed`
privately; it moves to this shared `ONBOARDING_DISMISS_COOKIE` constant and
`OnboardingController` references the shared one.

- `OnboardingController#show`: the existing
  `redirect_to prompts_path if @checklist.complete? || cookies[DISMISS_COOKIE]`
  becomes `redirect_to dashboard_path if workspace_ready?` (keeping the existing
  `return if params[:reset]` guard above it, so `?reset=1` still shows the
  checklist).
- `DashboardController#show`: `redirect_to onboarding_path unless workspace_ready?`.

`workspace_ready?` redirects from onboarding to the dashboard; its negation
redirects from the dashboard to onboarding. The conditions are exact
complements, so for any request at most one controller redirects. No loop.

### 5. Standalone app shrinks

- `standalone/app/controllers/home_controller.rb`: `index` becomes
  `redirect_to completion_kit.dashboard_path`. The `authenticate!` `before_action`
  and the `private` `authenticate!` method stay unchanged.
- Deleted: `standalone/app/views/home/index.html.erb`,
  `standalone/app/views/home/_concept.html.erb`,
  `standalone/app/helpers/home_helper.rb`.
- `standalone/config/routes.rb` is unchanged (`root to: "home#index"` still
  holds).

### 6. Concept tips on the engine onboarding

- Move the partial to `app/views/completion_kit/onboarding/_concept.html.erb`
  (engine). Its markup is unchanged except the `CONCEPTS` lookup namespace.
- Move the `CONCEPTS` data into the engine as
  `CompletionKit::Onboarding::Concepts::DEFINITIONS`, in a new file
  `app/services/completion_kit/onboarding/concepts.rb`. That sits beside the
  existing `app/services/completion_kit/onboarding/checklist.rb` and
  `sample_data.rb`. Keep all six definitions (provider credential, dataset,
  prompt, run, response, metric) for reuse, even though onboarding uses four.
- The onboarding checklist view renders one concept tip beside each step title.
  Map each `Checklist` step `key` to a concept key: `credential` ->
  `provider_credential`, `dataset` -> `dataset`, `prompt` -> `prompt`,
  `run` -> `run`.
- The `.ck-concept` CSS is already in the engine stylesheet from 0.5.30; no CSS
  change.

### 7. Engine topbar brand link

`app/views/layouts/completion_kit/application.html.erb`: the `.ck-brand` link
currently targets `main_app.root_path` (falling back to `prompts_path`). Point
it at `dashboard_path` so the logo returns to the dashboard.

## Testing

The engine enforces 100% line and branch coverage. New or changed engine code
that needs coverage:

- `DashboardController#show` — request specs: ready workspace renders the
  dashboard; not-ready workspace redirects to onboarding; `@run_count > 5`
  true and false (the activity-block branch); recent runs present and absent.
- `OnboardingController#show` — the redirect target is now `dashboard_path`;
  update the existing onboarding controller spec accordingly. Cover
  `workspace_ready?` via the dismiss cookie as well as `complete?`.
- The `_concept` partial and its rendering on the onboarding view — covered by
  the onboarding request spec rendering the page.
- `Onboarding::Concepts::DEFINITIONS` — a small model spec, or covered through
  the partial rendering.

The standalone app has no test suite; its code only shrinks, so there is
nothing to test there. A manual check: the standalone root redirects correctly
for a set-up and a fresh workspace.

## Out of scope

- Changing what `DashboardStats` computes, the `@run_count > 5` threshold, or
  the dashboard's visual design.
- Changing the dashboard-dismissal flow.
- A dashboard nav link in the topbar beyond pointing the brand logo at it.
- Tips for Response and Metric on the onboarding page (no matching step).
