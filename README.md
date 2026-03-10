# CompletionKit

[![CI](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml)
![coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)
[![CodeQL](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml)
![dependencies](https://img.shields.io/badge/dependencies-7-blue)
[![Dependabot](https://img.shields.io/badge/dependabot-enabled-blue?logo=dependabot)](https://github.com/homemade-software-inc/completion-kit/network/updates)

You need to know whether your prompts produce the output you expect, consistently, across real data. CompletionKit gives you that.

Mount it in any Rails app, feed it a prompt and a CSV of real inputs, and it runs every row through the model. Then it scores each output using configurable metrics and rubrics, flags regressions, and lets you compare versions side by side. When you change a prompt, you re-run the same dataset and see exactly what got better and what broke.

It's the difference between "this prompt seems to work" and "this prompt scores 8.4 across 200 inputs, up from 7.1 last version."

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

## Usage

1. Create a prompt with `{{variable}}` placeholders
2. Create a test run and paste CSV data (headers match variable names)
3. Generate outputs, run AI review, inspect scored results

## Eval DSL

Run prompt evaluations from code, in CI, or from the command line. Define evals in `evals/` and run them with rake:

```ruby
# evals/summarization_eval.rb
CompletionKit.define_eval("summarization") do |e|
  e.prompt "summarize_article"
  e.dataset "evals/fixtures/articles.csv"
  e.metric :relevance, threshold: 7.0
  e.metric :conciseness, threshold: 6.5
end
```

```bash
bundle exec rake completion_kit:eval           # run all evals
bundle exec rake completion_kit:eval:dry_run   # validate without API calls
bundle exec rake completion_kit:metrics        # list available metrics
```

See [docs/eval-dsl.md](docs/eval-dsl.md) for the full guide.

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
