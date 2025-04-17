# Codex Project Context: CompletionKit

## Overview
CompletionKit is a GenAI prompt testing platform packaged as a mountable Rails engine (gem `completion-kit`) compatible with Rails 7 and 8. It enables developers to create parameterized prompt templates, upload CSV datasets, run tests against various LLM providers (OpenAI, Anthropic, Llama), and evaluate output quality using an LLM-based judge.

## Architecture & Components
- **Engine**: Mounts under `/completion_kit` in host Rails apps via `CompletionKit::Engine`.
- **MVC Layers**:
  - **Models** (`app/models/completion_kit`):
    - `Prompt`: Stores prompt templates with `{{variable}}` placeholders and model selection.
    - `TestRun`: Represents a batch run against CSV data.
    - `TestResult`: Captures individual test outcomes, including input, raw output, expected output (optional), and quality score.
  - **Controllers** (`app/controllers/completion_kit`):
    - `PromptsController`, `TestRunsController`, `TestResultsController`.
  - **Views** (`app/views/completion_kit`): CRUD UIs for prompts, test runs, and results.
  - **Services/Clients** (`app/services/completion_kit`):
    - `OpenAiClient`, `AnthropicClient`, `LlamaClient`: HTTP clients wrapping LLM APIs (using Faraday).
    - `LlmClient`: Abstract client selecting provider.
    - `JudgeService`: Evaluates and scores outputs against expected results or criteria.
    - `CsvProcessor`, `ApiConfig`: CSV ingestion and API configuration helpers.

## Directory Structure (Top-Level)
```
./app         # Rails engine MVC code
./config      # Engine routes and init templates
./db/migrate  # Migrations: prompts, test_runs, test_results
./lib         # Gem and engine boot code (Engine, version)
Gemfile       # Uses `gemspec` for dependencies
completion-kit.gemspec  # Gem specification (dependencies, metadata)
README.md, Rakefile, MIT-LICENSE
```

## Routing
- Mount engine in host app `config/routes.rb`:
  ```ruby
  mount CompletionKit::Engine => "/completion_kit"
  ```

## Configuration
- **ENV Variables**:
  - `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `LLAMA_API_KEY`, `LLAMA_API_ENDPOINT`
- **Initializer** (optional):
  ```ruby
  CompletionKit.configure do |config|
    config.openai_api_key = '...'  # overrides ENV
  end
  ```

## Migrations & Setup
- Install migrations: `bin/rails completion_kit:install:migrations`
- Run: `bin/rails db:migrate`
- Development: `bundle install && bin/setup && rake spec`

## Usage Flow
1. Create a **Prompt** (use `{{var}}` syntax).
2. Create a **Test Run**, upload CSV with matching columns.
3. Execute run: LLM requests → stores **TestResults**.
4. Review and sort results by **quality score**; compare to expected output.

## Dependencies
- Runtime: Rails `>=7.0`, Ruby, Faraday, CSV, SassC, Bootstrap, jQuery
- Dev: RSpec, FactoryBot, SQLite3

---
*Last updated: $(date +"%Y-%m-%d")*