# Eval DSL Design — "RSpec for prompts"

## Problem

Rails apps with an AI component need a way to test prompt quality in CI. No Ruby-native tool exists. CompletionKit already has the scoring engine; it needs a code-first interface.

## Solution

A Ruby DSL that defines evals declaratively. A rake task runs them, scores outputs against metric thresholds, and exits non-zero on failure. Results are stored as test runs and viewable in the existing UI.

## DSL

```ruby
# evals/support_summary_eval.rb
CompletionKit.define_eval("support_summary") do |e|
  e.prompt "support_summary"
  e.dataset "evals/fixtures/support_summary.csv"
  e.judge_model "gpt-4.1"

  e.metric :relevance, threshold: 7.0
  e.metric :accuracy,  threshold: 8.0
  e.metric :tone,      threshold: 6.5
end
```

Eval files live in `evals/` at the Rails root. Convention: `evals/**/*_eval.rb`.

## Rake tasks

- `bundle exec rake completion_kit:eval` — run all evals, exit 1 on failure
- `bundle exec rake completion_kit:eval:dry_run` — validate definitions without API calls
- `bundle exec rake completion_kit:metrics` — list available metrics with keys

## CLI output

```
CompletionKit Evals

  support_summary ........................ 24 rows
    relevance    avg 8.2  (threshold 7.0)  pass
    accuracy     avg 8.7  (threshold 8.0)  pass
    tone         avg 7.1  (threshold 6.5)  pass

  translation ....... 7 rows
    relevance    avg 6.8  (threshold 7.0)  FAIL
    fluency      avg 9.1  (threshold 8.0)  pass

1 eval failed, 1 passed
Failed: translation — relevance scored 6.8, threshold 7.0
```

## Schema changes

One migration:

- `completion_kit_metrics.key` — string, unique index, auto-generated from name
- `completion_kit_test_runs.source` — string, default `"ui"`, values: `"ui"` or `"eval_dsl"`
- `completion_kit_test_runs.eval_name` — string, nullable

## New components

| Component | File | Purpose |
|---|---|---|
| Eval DSL | `lib/completion_kit/eval_dsl.rb` | `define_eval`, `EvalDefinition`, global registry |
| Eval runner | `lib/completion_kit/eval_runner.rb` | Load files, execute evals, compare thresholds |
| CLI formatter | `lib/completion_kit/eval_formatter.rb` | Terminal output with pass/fail per metric |
| Rake tasks | `lib/tasks/completion_kit_eval.rake` | Task definitions |

## Metric key mapping

Metrics get a `key` column (snake_case, unique). Auto-generated from name on create. DSL references metrics by key symbol. Unknown keys fail fast with available keys listed.

## What doesn't change

- All existing UI, views, controllers
- Rubric band system (5-level guidance)
- Provider credentials
- Prompt versioning and publishing
- Human review workflow
- Judge service

## CI integration

```yaml
- name: Run prompt evals
  run: bundle exec rake completion_kit:eval
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
```
