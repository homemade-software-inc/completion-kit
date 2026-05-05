# CompletionKit Standalone

A self-hosted prompt testing and evaluation service powered by the CompletionKit engine.

## Setup

```bash
bundle install
bin/rails completion_kit:install:migrations
bin/rails db:migrate
```

Then run **two processes** — a web server and a Solid Queue worker. In two terminals:

```bash
bin/rails server
```

```bash
bin/jobs
```

Or with [foreman](https://github.com/ddollar/foreman) in one terminal: `foreman start -f Procfile.dev`.

Visit `http://localhost:3000`.

## Processes

The standalone runs two cooperating processes:

| Process | Command | What it does |
|---------|---------|--------------|
| **web** | `bin/rails server` | Serves the UI and API |
| **worker** | `bin/jobs` | Runs Solid Queue jobs (LLM generation, judging, completion checks) |

Both processes need the same env-var set, including LLM provider keys and (in production) the three `COMPLETION_KIT_ENCRYPTION_*` keys. Without the worker process running, the UI works fine but generate/judge runs will sit at "running" forever — no jobs get processed.

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
| `SOLID_QUEUE_THREADS` | Worker thread pool size | `10` |
| `SOLID_QUEUE_PROCESSES` | Worker process count | `1` |
| `COMPLETION_KIT_LLM_CONCURRENCY` | Soft global cap on simultaneous LLM calls (must be ≤ `SOLID_QUEUE_THREADS`) | `10` |
| `COMPLETION_KIT_PER_RUN_CONCURRENCY` | Max simultaneous LLM calls per run | `5` |

## Database

Development and test use SQLite (zero config). For production, set `DATABASE_URL` to a PostgreSQL connection string.

## API

The REST API is available at `/completion_kit/api/v1/`. All requests require a bearer token:

```bash
curl -H "Authorization: Bearer $COMPLETION_KIT_API_TOKEN" http://localhost:3000/completion_kit/api/v1/prompts
```
