# CompletionKit Demo App

This app mounts the local `completion-kit` engine from the repository root and gives you a realistic host app for manual testing.

## Run It

```bash
cd examples/demo_app
bundle install --local
bin/rails db:migrate db:seed
bin/rails server
```

Then open:

- `/` for the Tailwind demo landing page
- `/completion_kit` for the mounted engine

## What Is Seeded

- One prompt: `Support Ticket Summarizer`
- One draft test run: `Seed Demo Run`

The demo app seeds prompt and CSV data so you can verify the UI immediately. To actually run a batch against a provider, configure an API key for the selected model in:

- `config/initializers/completion_kit.rb`
- or environment variables such as `OPENAI_API_KEY`
