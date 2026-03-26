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
