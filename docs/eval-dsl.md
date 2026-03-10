# Eval DSL

CompletionKit includes a code-first eval system for running prompt evaluations from the command line or CI. Think of it as RSpec for prompts: define what you expect, run it against real data, and get a pass/fail verdict.

## Quick Start

The install generator creates an `evals/` directory with an example:

```bash
bin/rails generate completion_kit:install
```

This gives you:

```
evals/
  example_eval.rb
  fixtures/
```

Edit `evals/example_eval.rb` and run:

```bash
bundle exec rake completion_kit:eval
```

## Defining Evals

Each eval file registers one or more evaluations using `CompletionKit.define_eval`:

```ruby
# evals/summarization_eval.rb
CompletionKit.define_eval("summarization_quality") do |e|
  e.prompt "summarize_article"
  e.dataset "evals/fixtures/articles.csv"
  e.judge_model "gpt-4.1"

  e.metric :relevance, threshold: 7.0
  e.metric :conciseness, threshold: 6.5
end
```

### `e.prompt(name)`

The name of the prompt to evaluate. Must match a prompt created in the CompletionKit UI. The system resolves the current (latest) version automatically.

### `e.dataset(path)`

Path to a CSV file relative to your Rails root. Column headers must match the `{{variable}}` placeholders in your prompt template.

```csv
content,audience,expected_output
"Rails 8 ships with Solid Cable",developers,"Summary of Rails 8 features"
"Q3 revenue grew 12%",executives,"Financial performance summary"
```

The `expected_output` column is optional. If present, the judge uses it as a reference when scoring.

### `e.judge_model(model)`

Which model to use for judging outputs. Defaults to the global `CompletionKit.config.judge_model` (which defaults to `gpt-4.1`).

### `e.metric(key, threshold:)`

Add a metric to evaluate against. The `key` is a symbol matching a metric's key in the database (auto-generated from the metric name via `parameterize`). The `threshold` is the minimum average score (1-10) required to pass.

You can add multiple metrics — the eval passes only if all metrics meet their thresholds.

List available metrics and their keys:

```bash
bundle exec rake completion_kit:metrics
```

## Running Evals

### Run All Evals

```bash
bundle exec rake completion_kit:eval
```

Loads every `*_eval.rb` file in `evals/`, runs each evaluation end-to-end, and prints results:

```
CompletionKit Evals

  summarization_quality  50 rows
    relevance            avg 8.2    (threshold 7.0 ) pass
    conciseness          avg 7.1    (threshold 6.5 ) pass

  classification         200 rows
    accuracy             avg 5.8    (threshold 7.0 ) FAIL

1 passed, 1 failed
Failed: classification — accuracy scored 5.8, threshold 7.0
```

Exits with code 1 if any eval fails — ready for CI.

### Dry Run

```bash
bundle exec rake completion_kit:eval:dry_run
```

Validates eval definitions without calling any APIs:

- Checks that the prompt exists
- Checks that the dataset file exists
- Checks that all metric keys are valid

```
CompletionKit Eval Dry Run

  summarization_quality  OK (50 rows, 2 metrics)

  classification  INVALID
    - Unknown metric key: accuracy
```

### List Metrics

```bash
bundle exec rake completion_kit:metrics
```

```
Available metrics:

  Relevance                 key: relevance
  Conciseness               key: conciseness
  Helpfulness               key: helpfulness
```

## What Happens During an Eval

1. **Prompt resolution** — finds the current version of the named prompt
2. **CSV parsing** — reads the dataset, maps columns to template variables
3. **Test run creation** — creates a `TestRun` record tagged with `source: "eval_dsl"`
4. **Output generation** — sends each row through the prompt's configured model
5. **Judging** — the judge model scores each output against every specified metric
6. **Scoring** — computes per-metric averages across all rows
7. **Verdict** — compares averages to thresholds, reports pass/fail

Eval runs are visible in the CompletionKit UI alongside manual test runs, tagged with an "eval" chip.

## CI Integration

Add to your CI pipeline:

```yaml
# .github/workflows/evals.yml
name: Prompt Evals

on:
  push:
    paths:
      - 'evals/**'
      - 'app/models/**/prompt.rb'

jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - name: Run evals
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          bin/rails db:prepare
          bundle exec rake completion_kit:eval
```

### Dry Run in PRs

Run validation without API costs on every PR:

```yaml
- name: Validate eval definitions
  run: |
    bin/rails db:prepare
    bundle exec rake completion_kit:eval:dry_run
```

## Multiple Evals per File

You can define multiple evals in a single file:

```ruby
# evals/all_prompts_eval.rb
CompletionKit.define_eval("summarization") do |e|
  e.prompt "summarize_article"
  e.dataset "evals/fixtures/articles.csv"
  e.metric :relevance, threshold: 7.0
end

CompletionKit.define_eval("classification") do |e|
  e.prompt "classify_ticket"
  e.dataset "evals/fixtures/tickets.csv"
  e.metric :accuracy, threshold: 8.0
end
```

## Creating Metrics

Metrics are created in the CompletionKit UI. Each metric has:

- **Name** — human-readable (e.g., "Relevance")
- **Key** — auto-generated from name (e.g., `relevance`), used in eval definitions
- **Guidance** — instructions for the judge model on what to look for
- **Rubric** — scoring bands (1-3 poor, 4-6 acceptable, 7-9 good, 10 excellent)

Metric groups bundle related metrics together and are assigned to prompts.

## Dataset Format

CSV files with headers matching your prompt's `{{variables}}`:

```csv
question,context,expected_output
"What is Ruby?","Programming language guide","Ruby is a dynamic programming language..."
"Explain Rails","Web framework docs","Rails is a web application framework..."
```

- Headers become template variables
- `expected_output` is optional but improves judge accuracy
- One row = one test case
- UTF-8 encoding recommended
