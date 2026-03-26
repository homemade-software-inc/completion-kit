# Standalone App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone deployable Rails app alongside the engine gem, replacing the demo app.

**Architecture:** Scaffold a minimal Rails app in `standalone/` that mounts the CompletionKit engine. It adds a home page with onboarding (empty state) and dashboard (active state). The demo app is deleted and all references updated.

**Tech Stack:** Rails 7.2, SQLite (dev), Postgres (prod option), RSpec

**Spec:** `docs/superpowers/specs/2026-03-26-standalone-app-design.md`

---

## Chunk 1: Scaffold and Configure

### Task 1: Scaffold the Standalone Rails App

**Files:**
- Create: `standalone/` directory with full Rails app scaffolding

- [ ] **Step 1: Generate the Rails app**

```bash
cd /Users/damien/Work/homemade/completion-kit
rails new standalone --minimal --skip-git --skip-test --skip-system-test --skip-docker
```

This creates a minimal Rails app with all the standard boilerplate (`bin/`, `config/`, `Rakefile`, `config.ru`, etc.) without tests (engine has its own), git (parent repo), or Docker.

- [ ] **Step 2: Remove unnecessary generated files**

```bash
rm -rf standalone/app/models standalone/app/mailers standalone/app/jobs standalone/app/channels
rm -rf standalone/app/views/layouts/mailer* standalone/storage standalone/lib standalone/vendor
rm -f standalone/app/controllers/concerns/.keep standalone/public/robots.txt
rm -f standalone/public/404.html standalone/public/406-unsupported-browser.html standalone/public/422.html standalone/public/500.html standalone/public/icon.png standalone/public/icon.svg
```

- [ ] **Step 3: Commit scaffolded app**

```bash
git add standalone/
git commit -m "scaffold: create standalone Rails app shell"
```

---

### Task 2: Configure Gemfile and Dependencies

**Files:**
- Modify: `standalone/Gemfile`

- [ ] **Step 1: Replace the generated Gemfile**

Write `standalone/Gemfile`:

```ruby
source "https://rubygems.org"

ruby "3.3.5"

gem "completion-kit", path: "../"
gem "puma"
gem "sqlite3"
gem "sprockets-rails"
gem "bootsnap", require: false

group :production do
  gem "pg"
end
```

- [ ] **Step 2: Run bundle install**

```bash
cd standalone && bundle install
```

- [ ] **Step 3: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/Gemfile standalone/Gemfile.lock
git commit -m "feat: configure standalone Gemfile with engine dependency"
```

---

### Task 3: Configure Database and Routes

**Files:**
- Modify: `standalone/config/database.yml`
- Modify: `standalone/config/routes.rb`
- Create: `standalone/config/initializers/completion_kit.rb`

- [ ] **Step 1: Update database.yml**

Write `standalone/config/database.yml`:

```yaml
default: &default
  adapter: sqlite3
  pool: 5
  timeout: 5000

development:
  <<: *default
  database: db/development.sqlite3

test:
  <<: *default
  database: db/test.sqlite3

production:
  url: <%= ENV["DATABASE_URL"] %>
```

- [ ] **Step 2: Update routes.rb**

Write `standalone/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  root to: "home#index"
  mount CompletionKit::Engine => "/completion_kit"
end
```

- [ ] **Step 3: Create CompletionKit initializer**

Write `standalone/config/initializers/completion_kit.rb`:

```ruby
CompletionKit.configure do |config|
  config.api_token = ENV["COMPLETION_KIT_API_TOKEN"]
  config.username = ENV.fetch("COMPLETION_KIT_USERNAME", "admin")
  config.password = ENV["COMPLETION_KIT_PASSWORD"]
end
```

- [ ] **Step 4: Install migrations and verify app boots**

```bash
cd standalone
bin/rails completion_kit:install:migrations
bin/rails db:migrate
bin/rails runner "puts 'App boots OK'"
```

Expected: No errors, migrations copied and run.

- [ ] **Step 5: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/config/ standalone/db/
git commit -m "feat: configure database, routes, and initializer for standalone app"
```

---

## Chunk 2: Home Page

### Task 4: HomeController

**Files:**
- Create: `standalone/app/controllers/home_controller.rb`

- [ ] **Step 1: Create the controller**

Write `standalone/app/controllers/home_controller.rb`:

```ruby
class HomeController < ActionController::Base
  layout "application"

  def index
    @has_data = CompletionKit::Prompt.any?
    if @has_data
      @prompt_count = CompletionKit::Prompt.current_versions.count
      @run_count = CompletionKit::Run.count
      @recent_runs = CompletionKit::Run.order(created_at: :desc).limit(5)
    end
  end
end
```

- [ ] **Step 2: Verify the controller loads**

```bash
cd standalone
bin/rails runner "HomeController"
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/app/controllers/home_controller.rb
git commit -m "feat: add HomeController with onboarding/dashboard logic"
```

---

### Task 5: Application Layout

**Files:**
- Modify: `standalone/app/views/layouts/application.html.erb`

The standalone app needs its own layout that matches the engine's dark theme. It includes the engine's stylesheet for `ck-*` CSS classes and replicates the nav structure.

- [ ] **Step 1: Write the layout**

Write `standalone/app/views/layouts/application.html.erb`:

```erb
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CompletionKit</title>
  <%= stylesheet_link_tag "completion_kit/application", media: "all" %>
</head>
<body>
  <header class="ck-top-bar">
    <div class="ck-wrap" style="display:flex; align-items:center; justify-content:space-between;">
      <a href="/" class="ck-brand">CompletionKit</a>
      <nav class="ck-top-nav">
        <a href="<%= completion_kit.prompts_path %>">Prompts</a>
        <a href="<%= completion_kit.metrics_path %>">Metrics</a>
        <a href="<%= completion_kit.datasets_path %>">Datasets</a>
        <a href="<%= completion_kit.runs_path %>">Runs</a>
        <a href="<%= completion_kit.provider_credentials_path %>">Settings</a>
      </nav>
    </div>
  </header>

  <main>
    <div class="ck-wrap">
      <% if notice %><p class="ck-flash ck-flash--notice"><%= notice %></p><% end %>
      <% if alert %><p class="ck-flash ck-flash--alert"><%= alert %></p><% end %>
      <%= yield %>
    </div>
  </main>
</body>
</html>
```

This reuses the engine's CSS classes (`ck-top-bar`, `ck-wrap`, `ck-brand`, `ck-top-nav`, `ck-flash`) and includes the engine's compiled stylesheet. Links use the `completion_kit` route proxy.

- [ ] **Step 2: Verify the layout renders**

```bash
cd standalone
bin/rails server &
sleep 3
curl -s http://localhost:3000 | head -20
kill %1
```

Expected: HTML response with the layout structure. May show an error about missing view template — that's OK, the layout itself renders.

- [ ] **Step 3: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/app/views/layouts/application.html.erb
git commit -m "feat: add application layout matching engine theme"
```

---

### Task 6: Home Page View

**Files:**
- Create: `standalone/app/views/home/index.html.erb`

This is the main home page with onboarding (empty state) and dashboard (active state). Use the `frontend-design` skill to design this view.

- [ ] **Step 1: Design and create the home page view**

Invoke the `frontend-design` skill to create `standalone/app/views/home/index.html.erb`. The design should:

- Use the engine's `ck-*` CSS classes for consistency
- Show onboarding when `@has_data` is false:
  - Welcome heading
  - Three steps with links via `completion_kit.*_path` helpers
- Show dashboard when `@has_data` is true:
  - Stats: `@prompt_count`, `@run_count`
  - Recent runs table: `@recent_runs` with name, status, score, timestamp
  - Links into engine UI
- Match the engine's dark theme aesthetic

- [ ] **Step 2: Verify the complete page renders**

```bash
cd standalone
bin/rails server &
sleep 3
curl -s http://localhost:3000 | grep -c "CompletionKit"
kill %1
```

Expected: At least 1 match (the brand in header). Page renders without errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/app/views/home/
git commit -m "feat: add home page with onboarding and dashboard views"
```

---

## Chunk 3: Cleanup and Documentation

### Task 7: Delete Demo App

**Files:**
- Delete: `examples/demo_app/` (entire directory)
- Delete: `examples/` (if empty after demo_app removal)

- [ ] **Step 1: Remove the demo app**

```bash
cd /Users/damien/Work/homemade/completion-kit
rm -rf examples/
```

- [ ] **Step 2: Verify engine tests still pass**

```bash
bundle exec rspec
```

Expected: All tests pass. The engine tests use `spec/dummy/`, not `examples/demo_app/`.

- [ ] **Step 3: Commit**

```bash
git rm -r examples/
git commit -m "chore: remove demo app (replaced by standalone/)"
```

---

### Task 8: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Replace demo app entries with standalone entries**

In `.gitignore`, replace:

```
examples/demo_app/tmp/
```

with:

```
standalone/tmp/
standalone/log/
standalone/db/*.sqlite3
standalone/db/*.sqlite3-*
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for standalone app"
```

---

### Task 9: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace demo app section with standalone section**

Find the demo app section in `README.md` and replace it with:

```markdown
## Standalone App

CompletionKit ships with a standalone Rails app you can deploy as a hosted service.

### Quick Start

```bash
cd standalone
bundle install
bin/rails completion_kit:install:migrations
bin/rails db:migrate
bin/rails server
```

Visit `http://localhost:3000` for the home page, or `http://localhost:3000/completion_kit` for the engine UI.

### Configuration

Set environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `COMPLETION_KIT_API_TOKEN` | Bearer token for REST API access | (none — API disabled) |
| `COMPLETION_KIT_USERNAME` | Web UI basic auth username | `admin` |
| `COMPLETION_KIT_PASSWORD` | Web UI basic auth password | (none — open in dev) |
| `DATABASE_URL` | PostgreSQL connection string (production) | SQLite in dev |
```

- [ ] **Step 2: Remove any other demo_app references in README**

Search for and remove/replace any remaining references to `demo_app`, `examples/demo_app`, or `examples/` in the README.

- [ ] **Step 3: Verify engine tests still pass**

```bash
bundle exec rspec
```

Expected: All tests pass, 100% coverage.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: replace demo app with standalone app in README"
```

---

### Task 10: Standalone README

**Files:**
- Create: `standalone/README.md`

- [ ] **Step 1: Write standalone README**

Write `standalone/README.md`:

```markdown
# CompletionKit Standalone

A self-hosted prompt testing and evaluation service powered by the CompletionKit engine.

## Setup

```bash
bundle install
bin/rails completion_kit:install:migrations
bin/rails db:migrate
bin/rails server
```

Visit `http://localhost:3000`.

## Configuration

All configuration is via environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `COMPLETION_KIT_API_TOKEN` | Bearer token for REST API | (none) |
| `COMPLETION_KIT_USERNAME` | Web UI username | `admin` |
| `COMPLETION_KIT_PASSWORD` | Web UI password | (none) |
| `DATABASE_URL` | PostgreSQL URL (production) | SQLite |
| `OPENAI_API_KEY` | OpenAI provider key | (none) |
| `ANTHROPIC_API_KEY` | Anthropic provider key | (none) |

## Database

Development and test use SQLite (zero config). For production, set `DATABASE_URL` to a PostgreSQL connection string.

## API

The REST API is available at `/completion_kit/api/v1/`. All requests require a bearer token:

```bash
curl -H "Authorization: Bearer $COMPLETION_KIT_API_TOKEN" http://localhost:3000/completion_kit/api/v1/prompts
```
```

- [ ] **Step 2: Commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
git add standalone/README.md
git commit -m "docs: add standalone app README"
```
