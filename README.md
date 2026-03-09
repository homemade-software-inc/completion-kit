# CompletionKit

[![CI](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/ci.yml)
![coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)
[![CodeQL](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml/badge.svg)](https://github.com/homemade-software-inc/completion-kit/actions/workflows/codeql.yml)
![dependencies](https://img.shields.io/badge/dependencies-7-blue)

A mountable Rails engine for testing LLM prompts against CSV datasets. Create prompts with `{{variable}}` placeholders, run them against OpenAI/Anthropic/Llama-compatible providers, and review scored results.

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
