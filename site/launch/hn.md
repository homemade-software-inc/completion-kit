# Hacker News submission

## Title

Show HN: CompletionKit -- Prompt regression testing across every model you use

## URL

https://completionkit.com

## First comment (post immediately after submission)

Hi HN -- I built CompletionKit because every prompt testing tool I tried was missing something.

Existing options are either provider-locked (OpenAI Evals, Anthropic Workbench), SaaS-paid (Braintrust, Humanloop, LangSmith), or CLI-only (Promptfoo). CompletionKit is a free, MIT-licensed Rails engine (with a bundled standalone app you can deploy without writing any Rails code) that runs prompt regression tests against your real data, scores outputs against custom rubrics with an LLM-as-judge, and supports OpenAI, Anthropic, Ollama, and 100+ models via OpenRouter.

The bit I'm proudest of: when scores tell you a prompt change made things worse, CompletionKit can read the LLM judge's per-response feedback and suggest an improved prompt grounded in those actual failures (not generic prompt-engineering best practices). You inspect the diff, accept or reject, and the new version is published with full history.

There's also a built-in MCP server so an agent like Claude Code can drive the whole loop -- read scores, ask for a suggestion, apply it, publish -- without leaving your IDE.

No hosted demo (intentionally -- I'd rather not babysit API spend on launch day) but the landing page has a 60-second walkthrough video and the README has a full setup guide.

Happy to answer questions, would love feedback. The blog post that goes deeper on the design: [LINK TO BLOG POST]
