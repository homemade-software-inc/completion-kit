# Standalone App Design

**Goal:** Ship a standalone deployable Rails app alongside the existing engine gem, so users can host CompletionKit as a service and access it via API or UI without embedding it in another Rails app.

---

## Approach

Keep the engine gem unchanged. Add a `standalone/` directory containing a minimal Rails app that mounts the engine. The existing `examples/demo_app/` is deleted and replaced by this.

Scaffold the standalone app with `rails new standalone --minimal` to get all the standard boilerplate (`bin/`, `config/environment.rb`, `config/environments/`, `Rakefile`, `config.ru`, etc.), then customize the generated files. This avoids hand-writing Rails boilerplate.

---

## Repo Structure

```
completion-kit/
├── app/                          # engine code (unchanged)
├── config/                       # engine config (unchanged)
├── db/                           # engine migrations (unchanged)
├── lib/                          # engine lib (unchanged)
├── spec/                         # engine specs (unchanged)
├── completion-kit.gemspec        # engine gem (unchanged)
├── standalone/                   # standalone Rails app (scaffolded via rails new)
│   ├── app/
│   │   ├── controllers/
│   │   │   └── home_controller.rb
│   │   └── views/
│   │       └── home/
│   │           └── index.html.erb
│   ├── config/
│   │   ├── application.rb
│   │   ├── database.yml
│   │   ├── environment.rb
│   │   ├── environments/
│   │   ├── routes.rb
│   │   └── initializers/
│   │       └── completion_kit.rb
│   ├── config.ru
│   ├── db/
│   ├── bin/
│   ├── Gemfile
│   ├── Rakefile
│   └── README.md
└── examples/demo_app/            # DELETED (replaced by standalone/)
```

---

## Standalone App Details

### Gemfile

```ruby
source "https://rubygems.org"

gem "completion-kit", path: "../"
gem "puma"
gem "sqlite3"
gem "sprockets-rails"

group :production do
  gem "pg"
end
```

`sqlite3` is needed explicitly (the engine only lists it as a dev dependency). `sprockets-rails` is needed for the engine's asset pipeline (stylesheets, JavaScript).

### Routes

```ruby
Rails.application.routes.draw do
  root to: "home#index"
  mount CompletionKit::Engine => "/completion_kit"
end
```

### Database

SQLite by default for development/test. Production requires `DATABASE_URL`.

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

### Initializer

```ruby
CompletionKit.configure do |config|
  config.api_token = ENV["COMPLETION_KIT_API_TOKEN"]
  config.username = ENV.fetch("COMPLETION_KIT_USERNAME", "admin")
  config.password = ENV["COMPLETION_KIT_PASSWORD"]
end
```

### Setup Commands

```bash
cd standalone
bundle install
bin/rails completion_kit:install:migrations
bin/rails db:migrate
bin/rails server
```

---

## Home Page

### Controller

The `HomeController` lives in the standalone app's namespace (NOT inside the engine). It inherits from `ActionController::Base` and uses its own layout that replicates the engine's look by including the engine's stylesheet.

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

The standalone app's `application.html.erb` layout includes the engine's stylesheet (`completion_kit/application`) and replicates the nav/header structure to match the engine's look.

Links to engine pages use the engine route proxy: `completion_kit.prompts_path`, `completion_kit.runs_path`, etc.

### View — Empty State (onboarding)

When no prompts exist, show:
- Welcome heading explaining what CompletionKit does
- Three setup steps linking to engine pages:
  1. Configure a provider key → `completion_kit.provider_credentials_path`
  2. Create your first prompt → `completion_kit.new_prompt_path`
  3. Run an evaluation → `completion_kit.new_run_path`
- Uses the engine's CSS classes (`ck-*`) for consistent styling

### View — Active State (dashboard)

When data exists, show:
- Stats row: prompt count, run count, latest average score
- Recent runs table: last 5 runs with name, status, score, timestamp
- Quick action links into the engine UI (via route proxy)

Both states use the engine's design system (`ck-*` CSS classes) via the engine stylesheet.

The view should be designed using the `frontend-design` skill for a polished, distinctive experience.

---

## What Gets Deleted

- `examples/demo_app/` — entire directory

## What Gets Updated

- `README.md` — replace demo app references with standalone app instructions
- `.gitignore` — replace `examples/demo_app/tmp/` with `standalone/tmp/`, `standalone/db/*.sqlite3`, `standalone/log/`

## What Stays Unchanged

- All engine code (`app/`, `config/`, `db/`, `lib/`, `spec/`)
- The gemspec
- Engine tests
- CI workflow (does not reference `demo_app`)
- Historical docs in `docs/superpowers/plans/` (left as-is)

---

## Out of Scope

- Docker
- Deploy platform guides (Heroku, Fly, Render)
- Client SDKs for other languages
- User accounts / multi-tenancy
