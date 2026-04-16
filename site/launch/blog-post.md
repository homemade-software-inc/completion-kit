# CompletionKit: prompt regression testing for every model you use

[REPLACE WITH YOUR REAL STORY]

That's the problem CompletionKit solves.

## What it does

CompletionKit is a free, MIT-licensed prompt testing platform. You mount it as a Rails engine or run it as a standalone app (no Rails experience needed).

The workflow: you create a prompt with `{{variable}}` placeholders, upload a CSV of real inputs, define metrics with rubric bands (what does a 5/5 look like? what's a 1?), and hit run. CompletionKit sends every row through the model you pick, then an LLM-as-judge scores each output against your rubrics. You get a score breakdown per metric, per row, with the judge's written reasoning.

When you change the prompt, you re-run the same dataset and see exactly what got better and what broke. Every edit forks a new version automatically. Full history preserved.

[DEMO GIF OR LOOM EMBED HERE]

The part that surprised me most during development: the AI-suggested improvements. When your scores drop, CompletionKit reads the judge's per-response feedback from your actual runs and proposes a fix grounded in those specific failures -- not generic prompt-engineering advice. You see a diff, accept or reject, and the new version publishes with the full change history intact.

There's also a REST API with bearer-token auth and a built-in MCP server with 36 tools. An agent like Claude Code can read your scores, request a suggestion, apply it, and publish a new version without you leaving the IDE. That loop -- run, score, suggest, apply, re-run -- is the core of what CompletionKit is for.

## What makes it different

I built CompletionKit because the existing options each had a piece missing.

**OpenAI Evals** and **Anthropic Workbench** are great if you only use one provider. They're free, integrated, and the path of least resistance. But they don't help when you want to compare the same prompt across `gpt-5`, `claude-sonnet-4-6`, and your local Ollama instance. CompletionKit runs the same dataset against all of them in one place.

**Braintrust**, **Humanloop**, and **LangSmith** all do multi-provider, but they're SaaS and they're paid. For an indie team or a solo dev, the per-seat pricing is hard to justify before you've validated the prompt-testing workflow at all. CompletionKit is MIT-licensed and self-hosted. No bill, no vendor lock-in.

**Promptfoo** is the closest open-source competitor -- multi-provider, free, well-maintained. It's CLI/YAML-first though, which means it lives in your test suite, not in your team's day-to-day workflow. CompletionKit goes the other direction: a Rails-native UI for prompt management, runs, and versioning, with the same evaluation rigor underneath.

**Langfuse** is the strongest direct competitor -- open source, self-hostable, multi-provider. The difference is scope: Langfuse is observability + traces + evals + prompt management, designed for teams that want all of it. CompletionKit is focused on prompt testing well, with versioning, AI-driven improvement suggestions grounded in your actual run data, and an MCP server so AI agents can drive the whole workflow end-to-end.

## What's in 0.1.0

- Web UI for prompts, datasets, runs, metrics, and provider credentials
- LLM-as-judge with custom rubrics (1-5 star bands)
- Multi-provider: OpenAI, Anthropic, Ollama (or any OpenAI-compatible endpoint), 100+ models via OpenRouter
- Versioned prompts with AI-driven improvement suggestions
- REST API with bearer-token auth
- MCP server with 36 tools so Claude Code or any other MCP client can drive it
- 100% test coverage
- Encrypted provider credentials at rest
- MIT-licensed

## Try it

```ruby
gem "completion-kit"
```

```bash
bin/rails generate completion_kit:install
bin/rails db:migrate
bin/rails server
```

Open `/completion_kit` in your browser. The README has a [full walkthrough](https://github.com/homemade-software-inc/completion-kit#readme).

Not a Rails developer? Run the bundled standalone app -- same features, no Rails experience required. Instructions in the [README](https://github.com/homemade-software-inc/completion-kit#standalone-app).

Providers supported out of the box: OpenAI, Anthropic, Ollama (or any OpenAI-compatible local endpoint), and 100+ models via OpenRouter. Add your API keys in the UI and you're running.

## What's next

This is 0.1.0. The core loop works well: create prompts, run them against real data, score them, iterate. The things I'm thinking about next are search/filtering for large model lists, background job processing for heavier workloads, and whatever the first batch of users tell me is missing.

Landing page: [completionkit.com](https://completionkit.com)
GitHub: [github.com/homemade-software-inc/completion-kit](https://github.com/homemade-software-inc/completion-kit)
RubyGems: [rubygems.org/gems/completion-kit](https://rubygems.org/gems/completion-kit)

I'd like to hear what's broken and what's missing. Open an issue on [GitHub](https://github.com/homemade-software-inc/completion-kit/issues) or find me on X.

-- Damien
