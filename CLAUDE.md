# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Claude Code Usage

Invoke Claude Code from the project root with:
```bash
claude --permission-mode bypassPermissions --print 'your prompt here'
```

Use `--print` for non-interactive mode (no PTY needed). The `--permission-mode bypassPermissions` flag allows Claude Code to make edits without manual approval.

For longer tasks, use background mode:
```bash
claude --permission-mode bypassPermissions --print 'your task' &
```

## Standalone App
- Logs: `standalone/log/` (check `development.log` for runtime errors)
- Rails runner: `cd standalone && bin/rails runner "..."`
- Server: `cd standalone && bin/rails s`

## Build/Test Commands
- Install dependencies: `bundle install`
- Run all tests: `bundle exec rake spec` or `bundle exec rspec`
- Run single test: `bundle exec rspec path/to/spec_file.rb:line_number`
- Run specific test file: `bundle exec rspec path/to/spec_file.rb`
- Install engine migrations into standalone: `cd standalone && bin/rails completion_kit:install:migrations` (run locally, commit the generated file, push — Render only runs `db:migrate`)
- Run migrations: `bin/rails db:migrate`
- Install gem locally: `bundle exec rake install`

## Code Style Guidelines
- Namespace all code under `CompletionKit` module
- Follow Rails naming conventions (CamelCase for classes, snake_case for methods)
- Use YARD-style comments (@param, @return) for service classes
- Raise `NotImplementedError` for abstract methods that subclasses must implement
- Place private methods at the bottom of classes
- Use standard RESTful controllers with strong parameters
- Models should include validations and associations at the top
- Follow test-driven development using RSpec and FactoryBot
- Maintain 100% line and branch coverage — CI enforces this
- Wrap LLM API calls in service classes with consistent interfaces