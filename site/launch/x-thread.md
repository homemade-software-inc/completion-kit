# X thread (pin on launch day)

## Tweet 1

Just shipped CompletionKit 0.1.0 -- prompt regression testing for every model you use.

Free, MIT-licensed, self-hostable. Works with OpenAI, Anthropic, Ollama, and 100+ models via OpenRouter.

[DEMO GIF]

https://completionkit.com

## Tweet 2

The problem: you change a prompt, you think it works better, you ship it. Two weeks later an edge case you forgot to test surfaces in production.

Manual testing always misses edge cases. CompletionKit catches them before you ship.

## Tweet 3

You bring real data and your own rubrics. The LLM-as-judge scores every output against your criteria.

Change the prompt, re-run the same dataset, see exactly what got better and what broke.

[SCREENSHOT]

## Tweet 4

Install in 30 seconds:

gem "completion-kit"

bin/rails generate completion_kit:install
bin/rails db:migrate

Or run the bundled standalone app -- no Rails experience required.

## Tweet 5

When a score drops, CompletionKit reads the judge's actual feedback and suggests a fixed prompt grounded in those real failures. You inspect the diff and apply as a new version.

Built-in MCP server so Claude Code can drive the whole loop end-to-end.

## Tweet 6

Free forever, MIT, 100% test coverage, no SaaS lock-in.

-> https://completionkit.com
-> https://github.com/homemade-software-inc/completion-kit
-> https://rubygems.org/gems/completion-kit

Try it. Tell me what's broken.
