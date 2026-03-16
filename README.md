# CompletionKit

[![CI](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml)
![coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)
![dependencies](https://img.shields.io/badge/dependencies-7-blue)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-blue?logo=dependabot)](https://github.com/homemade-software-inc/completion-kit/network/updates)

You need to know whether your prompts produce the output you expect, consistently, across real data. CompletionKit gives you that.

Mount it in any Rails app, feed it a prompt and a CSV of real inputs, and it runs every row through the model. Then it scores each output using configurable metrics and rubrics, flags regressions, and lets you compare versions side by side. When you change a prompt, you re-run the same dataset and see exactly what got better and what broke.

It's the difference between "this prompt seems to work" and "this prompt scores 8.4 across 200 inputs, up from 7.1 last version."

![Prompts index](docs/screenshots/prompts.png)

![Prompt detail with metrics and rubrics](docs/screenshots/prompt-detail.png)

![Test run with scored results](docs/screenshots/test-run.png)

## Setup

```ruby
gem "completion-kit"
```

```bash
bin/rails generate completion_kit:install
bin/rails db:migrate
```

Set your provider keys via environment variables or the generated initializer:

```bash
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
LLAMA_API_KEY=...
LLAMA_API_ENDPOINT=...
```

Available models are discovered dynamically from each provider's API.

## Authentication

CompletionKit requires authentication in production. In development, routes are open by default (with a log warning).

### Basic Auth (recommended for simple setups)

```ruby
# config/initializers/completion_kit.rb
CompletionKit.configure do |c|
  c.username = "admin"
  c.password = ENV["COMPLETION_KIT_PASSWORD"]
end
```

### Custom Auth (Devise, etc.)

```ruby
# config/initializers/completion_kit.rb
CompletionKit.configure do |c|
  c.auth_strategy = ->(controller) { controller.authenticate_user! }
end
```

Only one mode can be active — setting both raises a `ConfigurationError`.

## Usage

1. Create a prompt with `{{variable}}` placeholders
2. Create a test run and paste CSV data (headers match variable names)
3. Generate outputs, run AI review, inspect scored results

## REST API

CompletionKit provides a JSON API for programmatic access to all resources.

### Configuration

```ruby
CompletionKit.configure do |config|
  config.api_token = ENV['COMPLETION_KIT_API_TOKEN']
end
```

### Authentication

All API requests require a bearer token:

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3000/completion_kit/api/v1/prompts
```

### Endpoints

| Resource | Endpoints |
|----------|-----------|
| Prompts | `GET/POST /api/v1/prompts`, `GET/PATCH/DELETE /api/v1/prompts/:id`, `POST /api/v1/prompts/:id/publish`, `POST /api/v1/prompts/:id/new_version` |
| Runs | `GET/POST /api/v1/runs`, `GET/PATCH/DELETE /api/v1/runs/:id`, `POST /api/v1/runs/:id/generate`, `POST /api/v1/runs/:id/judge` |
| Responses | `GET /api/v1/runs/:run_id/responses`, `GET /api/v1/runs/:run_id/responses/:id` |
| Datasets | `GET/POST /api/v1/datasets`, `GET/PATCH/DELETE /api/v1/datasets/:id` |
| Metrics | `GET/POST /api/v1/metrics`, `GET/PATCH/DELETE /api/v1/metrics/:id` |
| Criteria | `GET/POST /api/v1/criteria`, `GET/PATCH/DELETE /api/v1/criteria/:id` |
| Provider Credentials | `GET/POST /api/v1/provider_credentials`, `GET/PATCH/DELETE /api/v1/provider_credentials/:id` |

### Examples

**Create a prompt:**

```bash
curl -X POST http://localhost:3000/completion_kit/api/v1/prompts \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "summarizer", "template": "Summarize: {{text}}", "llm_model": "gpt-4.1"}'
```

**Create a run and generate responses:**

```bash
curl -X POST http://localhost:3000/completion_kit/api/v1/runs \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prompt_id": 1, "dataset_id": 1}'

curl -X POST http://localhost:3000/completion_kit/api/v1/runs/1/generate \
  -H "Authorization: Bearer YOUR_TOKEN"

curl -X POST http://localhost:3000/completion_kit/api/v1/runs/1/judge \
  -H "Authorization: Bearer YOUR_TOKEN"

curl http://localhost:3000/completion_kit/api/v1/runs/1/responses \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Development

```bash
bundle install
bundle exec rspec
```

Demo app:

```bash
cd examples/demo_app
bin/rails db:migrate db:seed
bin/rails server
```

## License

[MIT](https://opensource.org/licenses/MIT)
