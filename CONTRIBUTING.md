# Contributing to CompletionKit

Thanks for your interest in contributing! This document describes how to
get set up, run the tests, and submit changes.

## Code of Conduct

This project and everyone participating in it is governed by the
[CompletionKit Code of Conduct](CODE_OF_CONDUCT.md). By participating,
you are expected to uphold this code. Please report unacceptable
behavior to [damien@homemade.software](mailto:damien@homemade.software).

## Ways to Contribute

- **Report bugs** — open an issue with a minimal reproduction, the
  version you're running, and the expected vs. actual behavior.
- **Suggest features** — open an issue describing the use case before
  writing code, so we can discuss scope and design.
- **Submit pull requests** — bug fixes, documentation improvements, and
  small features are welcome without prior discussion. For larger
  changes, please open an issue first.

## Development Setup

### Requirements

- Ruby 3.1 or newer (CI runs on 3.3)
- Bundler
- SQLite3 (for the standalone demo app)

### Getting Started

```bash
git clone https://github.com/homemade-software-inc/completion-kit.git
cd completion-kit
bundle install
```

### Running the Standalone App

The repository includes a standalone Rails app under `standalone/` that
mounts the engine for local development.

```bash
cd standalone
bundle install
bin/rails db:migrate
bin/rails s
```

Then open `http://localhost:3000`.

Copy `standalone/.env.example` to `standalone/.env` and populate it with
LLM provider API keys if you want to exercise generate/judge flows.

## Running the Tests

CompletionKit uses RSpec and enforces 100% line and branch coverage in
CI. Pull requests that drop coverage will fail.

```bash
bundle exec rspec                              # run the full suite
bundle exec rspec spec/models/prompt_spec.rb   # run a single file
bundle exec rspec spec/models/prompt_spec.rb:42 # run a single example
```

After a run, a coverage report is written to `coverage/index.html`.

## Code Style

- Namespace all code under the `CompletionKit` module.
- Follow Rails naming conventions: `CamelCase` for classes,
  `snake_case` for methods and files.
- Use YARD-style comments (`@param`, `@return`) on service classes.
- Raise `NotImplementedError` for abstract methods that subclasses must
  implement.
- Private methods go at the bottom of the class.
- Wrap LLM API calls in service classes with consistent interfaces.
- Write tests first. The 100% coverage gate is not a formality — it
  catches dead code and forces honest design.

## Submitting a Pull Request

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests.
3. Run `bundle exec rspec` locally and confirm the suite is green and
   coverage is 100%.
4. Write a clear commit message describing the "why", not just the "what".
5. Open a pull request against `main`. Link any related issues.
6. CI will run tests, CodeQL, and Dependabot checks. Address any
   failures before requesting review.

## License

By contributing to CompletionKit, you agree that your contributions from
version 0.3.0 onward will be licensed under the [Business Source License
1.1](LICENSE). Versions 0.2.x and earlier remain under the [MIT
License](https://github.com/homemade-software-inc/completion-kit/blob/v0.2.0/MIT-LICENSE).
