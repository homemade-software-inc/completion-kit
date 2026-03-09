# CompletionKit

[![CI](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml)
![coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)
[![CodeQL](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml)
![dependencies](https://img.shields.io/badge/dependencies-7-blue)

CompletionKit is a mountable Rails engine for testing prompt templates against CSV datasets inside a host Rails app. It gives you a small UI for managing prompts, running prompt batches against supported LLM providers, and reviewing scored results.

## What It Does

- Create and edit prompt templates with `{{variable}}` placeholders
- Create CSV-backed test runs for those prompts
- Execute prompt batches against OpenAI, Anthropic, or Llama-compatible providers
- Store generated outputs per row as test results
- Evaluate outputs with an LLM judge
- Review result detail pages with score, feedback, sorting, filtering, and expected-output comparison

## Requirements

- Ruby 3.3
- Rails 7.x or 8.x
- A host app database supported by Active Record
- At least one configured LLM provider API key for the model you want to run

## Installation

### 1. Add the gem

In your host app `Gemfile`:

```ruby
gem "completion-kit"
```

Then install dependencies:

```bash
bundle install
```

If you want to install the gem directly:

```bash
gem install completion-kit
```

### 2. Install the engine into your app

Preferred setup:

```bash
bin/rails generate completion_kit:install
```

That generator adds the initializer template, mounts the engine route, and installs the engine migrations into the host app.

Manual fallback:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount CompletionKit::Engine => "/completion_kit"
end
```

### 3. Run migrations

If you used the generator, it already copied the migrations. Otherwise:

```bash
bin/rails completion_kit:install:migrations
```

Then migrate:

```bash
bin/rails db:migrate
```

### 4. Configure provider credentials

CompletionKit reads provider credentials from either the initializer or environment variables.

Supported environment variables:

```bash
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
LLAMA_API_KEY=...
LLAMA_API_ENDPOINT=...
```

Initializer example:

```ruby
# config/initializers/completion_kit.rb
CompletionKit.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.llama_api_key = ENV["LLAMA_API_KEY"]
  config.llama_api_endpoint = ENV["LLAMA_API_ENDPOINT"]

  config.judge_model = "gpt-4"
  config.high_quality_threshold = 80
  config.medium_quality_threshold = 50
end
```

## Usage

### Create a prompt

1. Visit `/completion_kit/prompts`
2. Create a prompt with a name, description, model, and template
3. Use `{{variable}}` placeholders for fields that will come from CSV data

Example template:

```text
Summarize this text for {{audience}}:

{{content}}
```

### Create a test run

1. Open a prompt
2. Create a new test run
3. Paste CSV data into the test run form
4. Make sure CSV headers match the prompt variables

Example CSV:

```csv
content,audience,expected_output
"Release notes for v1.2","developers","A concise developer-facing summary"
"Quarterly results memo","executives","A short executive summary"
```

The `expected_output` column is optional, but it improves result comparison and evaluation.

### Run and evaluate

1. Run the test batch from the test run page
2. Review generated outputs per row
3. Evaluate results with the configured judge model
4. Sort and filter by quality score or creation time

## Models and Providers

CompletionKit discovers available models dynamically from each configured provider's API. When a provider API key is set, the engine queries the provider's model listing endpoint and populates the model dropdowns automatically. If the API is unreachable, it falls back to a small static list per provider.

Supported providers: **OpenAI**, **Anthropic**, and **Llama-compatible** (any OpenAI-compatible endpoint). Provider client adapters live inside the engine and use Faraday for HTTP requests.

## Development

Install dependencies:

```bash
bundle install
```

Run the test suite:

```bash
bundle exec rspec
```

Or via rake:

```bash
bundle exec rake spec
```

### Coverage

The test suite is gated by SimpleCov with:

- 100% line coverage
- 100% branch coverage

Coverage output is written to:

```text
coverage/index.html
```

### Demo App

A local host app for manual testing lives in:

```text
examples/demo_app
```

To boot it:

```bash
cd examples/demo_app
bundle install --local
bin/rails db:migrate db:seed
bin/rails server
```

## CI

GitHub Actions runs the same coverage-gated spec suite on `push` and `pull_request`, and uploads the generated `coverage/` directory as a build artifact.

## License

CompletionKit is released under the [MIT License](https://opensource.org/licenses/MIT).
