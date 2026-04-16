# r/rails post

## Title

CompletionKit: a mountable Rails engine for prompt regression testing (MIT, just shipped 0.1.0)

## Body

Hi r/rails -- just shipped 0.1.0 of CompletionKit, a free open-source Rails engine for testing GenAI prompts against real data.

You mount it in your Rails app (or run the bundled standalone), bring a CSV of real inputs and a prompt with `{{variable}}` placeholders, and CompletionKit runs every row through the model you pick. An LLM-as-judge scores each output against your custom rubrics (1-5 star bands), and when you change a prompt you re-run the same dataset and see exactly what got better and what broke.

What I think makes it different from the other prompt testing tools:

- **Multi-provider**: OpenAI, Anthropic, Ollama (any OpenAI-compatible local endpoint), and 100+ models via OpenRouter -- all in one tool
- **AI-driven suggestions**: when the scores drop, CompletionKit reads the LLM judge's actual feedback and proposes a fixed prompt grounded in the real failures, not generic best practices
- **Versioned prompts**: every edit forks a new version automatically, full history preserved
- **REST API + MCP server**: built-in MCP server with 36 tools so Claude Code or any other MCP client can drive the workflow

100% test coverage, MIT-licensed, no SaaS lock-in, no per-seat pricing.

- Landing page: https://completionkit.com
- GitHub: https://github.com/homemade-software-inc/completion-kit
- Blog post: [LINK TO BLOG POST]

Happy to answer questions, would love feedback on what's broken or missing.
