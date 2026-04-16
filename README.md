<p align="center">
  <img src="https://raw.githubusercontent.com/homemade-software-inc/completion-kit/main/docs/logo.png" alt="CompletionKit" width="360" />
</p>

<p align="center">
  <a href="https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml"><img src="https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/coverage-100%25-brightgreen" alt="coverage" />
</p>

Your prompts need tests too.

Run every prompt against real data. Score each output with an LLM judge against criteria you define. Change anything: the prompt, the model, the temperature, the dataset. Re-run and see exactly what got better and what broke. When the scores tell you something's off, CompletionKit suggests an improved prompt based on the judge's actual feedback on your runs. You inspect the diff, apply it as a new version, and verify the improvement.

It's the difference between "this prompt seems to work" and "this prompt scores 4.3 out of 5 across 200 inputs, up from 3.8 last version."

**[completionkit.com](https://completionkit.com)** | **[RubyGems](https://rubygems.org/gems/completion-kit)**

![Prompts index](https://raw.githubusercontent.com/homemade-software-inc/completion-kit/main/docs/screenshots/prompts.png)

![Prompt detail with metrics and rubrics](https://raw.githubusercontent.com/homemade-software-inc/completion-kit/main/docs/screenshots/prompt-detail.png)

![Test run with scored results](https://raw.githubusercontent.com/homemade-software-inc/completion-kit/main/docs/screenshots/test-run.png)

## Quick Start

### Run the standalone app

The fastest way to start. No existing Rails app needed.

```bash
git clone https://github.com/homemade-software-inc/completion-kit.git
cd completion-kit/standalone
bundle install
bin/rails completion_kit:install:migrations
bin/rails db:migrate
bin/rails server
```

Visit `http://localhost:3000`. Add a provider credential (Settings), create a prompt, upload a CSV dataset, and run it.

### Or mount as an engine in your existing Rails app

```ruby
gem "completion-kit"
```

```bash
bin/rails generate completion_kit:install
bin/rails db:migrate
```

The engine mounts at `/completion_kit` in your app.

## Providers

CompletionKit discovers available models from each provider's API automatically.

| Provider | Env vars | What it covers |
|----------|----------|----------------|
| **OpenAI** | `OPENAI_API_KEY` | GPT-5, GPT-4.1, GPT-4o, etc. |
| **Anthropic** | `ANTHROPIC_API_KEY` | Claude Opus, Sonnet, Haiku |
| **Ollama / local endpoint** | `OLLAMA_API_ENDPOINT` (default: `http://localhost:11434/v1`) | Any model you've `ollama pull`-ed, or any OpenAI-compatible local server (vLLM, LM Studio, llama.cpp) |
| **OpenRouter** | `OPENROUTER_API_KEY` | 100+ models from 30+ providers through one API key |

Set these as environment variables or configure them in the generated initializer. You can also add provider credentials through the web UI under Settings.

### Encryption

Provider API keys are encrypted at rest using [Active Record encryption](https://guides.rubyonrails.org/active_record_encryption.html). You need three encryption keys configured before the app will boot in production.

Generate them:

```bash
bin/rails db:encryption:init
```

Then set them as environment variables:

```bash
COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY=<generated value>
COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY=<generated value>
COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT=<generated value>
```

Or add them to `config/credentials.yml.enc` under `active_record_encryption`. In development, the standalone app uses built-in fallback values so you can skip this step locally.

## Authentication

CompletionKit requires authentication in production. In development, routes are open by default (with a log warning).

### Basic Auth (recommended for simple setups)

```ruby
CompletionKit.configure do |c|
  c.username = "admin"
  c.password = ENV["COMPLETION_KIT_PASSWORD"]
end
```

### Custom Auth (Devise, etc.)

```ruby
CompletionKit.configure do |c|
  c.auth_strategy = ->(controller) { controller.authenticate_user! }
end
```

Only one mode can be active.

## How it works

1. **Create a prompt** with `{{variable}}` placeholders
2. **Upload a dataset.** A CSV where column headers match the variable names.
3. **Run it** against a model and score outputs with an LLM judge against criteria you define.
4. **Iterate.** Change the prompt, the model, the temperature, or the dataset and re-run. CompletionKit versions your prompts so you can always compare against previous results.
5. **Get suggestions.** When scores drop, ask CompletionKit for an AI-generated improvement. The suggestion is based on the judge's actual per-response feedback, not generic prompt-engineering advice. Inspect the diff and apply it as a new version.

## Concepts

- **Prompt.** A versioned template with `{{variable}}` placeholders. Publishing freezes the template; editing a published prompt creates a new version.
- **Dataset.** A CSV of real inputs. Each row becomes one test case.
- **Run.** One execution of a prompt against a dataset. Captures every input (model, temperature, metrics) and stores all outputs and scores.
- **Response.** The model's output for one dataset row, with reviews attached.
- **Metric.** An evaluation dimension with a name, instruction, evaluation steps, and a 1-5 star scoring scale. The LLM judge uses this to score each response.
- **Criteria.** A reusable bundle of metrics.
- **Provider Credential.** An API key for a model provider. Encrypted at rest, never returned through the API.

## REST API

Every resource is accessible via a bearer-token JSON API:

```ruby
CompletionKit.configure { |c| c.api_token = ENV["COMPLETION_KIT_API_TOKEN"] }
```

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/completion_kit/api/v1/prompts
```

Visit `/completion_kit/api_reference` in your running app for per-endpoint docs with copy-to-clipboard curl examples.

## MCP server

CompletionKit runs a [Model Context Protocol](https://modelcontextprotocol.io) server at `/completion_kit/mcp`, exposing every resource as tools that MCP-aware clients (Claude Code, Cursor, etc.) can drive directly:

```json
{
  "mcpServers": {
    "completion-kit": {
      "url": "https://your-app.com/completion_kit/mcp",
      "headers": { "Authorization": "Bearer YOUR_TOKEN" }
    }
  }
}
```

The in-app API reference page has install snippets you can copy straight into your MCP client config.

## Deploying the standalone app

Any Rails-friendly host works (Fly, Heroku, Render, Docker, etc.). Point it at a Postgres instance via `DATABASE_URL`, set your provider env vars, and run `cd standalone && bin/rails db:migrate` on each deploy.

| Variable | Purpose | Default |
|----------|---------|---------|
| `COMPLETION_KIT_API_TOKEN` | Bearer token for REST API and MCP | (none, API disabled) |
| `COMPLETION_KIT_USERNAME` | Web UI login username | `admin` |
| `COMPLETION_KIT_PASSWORD` | Web UI login password | (none, open in dev) |
| `COMPLETION_KIT_ENCRYPTION_PRIMARY_KEY` | AR encryption key | (required in production) |
| `COMPLETION_KIT_ENCRYPTION_DETERMINISTIC_KEY` | AR encryption key | (required in production) |
| `COMPLETION_KIT_ENCRYPTION_KEY_DERIVATION_SALT` | AR encryption key | (required in production) |

When the gem ships a new migration, install it locally and commit before pushing:

```bash
cd standalone
bin/rails completion_kit:install:migrations
bin/rails db:migrate
git add db/migrate/ && git commit -m "install new engine migration"
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing, and pull request guidelines.

## License

[MIT](https://opensource.org/licenses/MIT)
