# Authentication & Feature Audit Design

**Goal:** Add password protection to the CompletionKit engine and verify all features work end-to-end.

**Two independent workstreams:**
1. Authentication — protect all engine routes
2. Feature audit — verify and fix the full pipeline

---

## Part 1: Authentication

### Configuration API

Two mutually exclusive modes, configured via the existing `CompletionKit.configure` block.

#### Mode A: Built-in HTTP Basic Auth

```ruby
CompletionKit.configure do |c|
  c.username = "admin"
  c.password = Rails.application.credentials.completion_kit_password
end
```

Adds `http_basic_authenticate_with` behavior to the engine's `ApplicationController`. All engine routes require the configured username and password.

#### Mode B: Custom Auth Hook

```ruby
CompletionKit.configure do |c|
  c.auth_strategy = ->(controller) { controller.authenticate_user! }
end
```

A lambda/proc that receives the controller instance. Called as a `before_action` on every engine request. The host app owns the auth logic entirely. The lambda is responsible for halting the request itself (e.g., by calling `render`, `redirect_to`, or `head :unauthorized`), just like Devise's `authenticate_user!`.

### Conflict Detection

If both `password` and `auth_strategy` are configured, raise `CompletionKit::ConfigurationError` on the first request with a clear message: "Cannot configure both username/password and auth_strategy. Use one or the other."

If only one of `username` or `password` is set (but not both), raise `CompletionKit::ConfigurationError`: "Both username and password are required for built-in auth."

Raised at request time (not boot time) because engine initializer order is unpredictable.

### No Auth Configured

- **Development/test environments:** Open access. Log a boot-time warning via `after_initialize`: `[CompletionKit] WARNING: No authentication configured. All routes are publicly accessible.`
- **Production environment:** Hard block. Every engine route renders an error page: "CompletionKit authentication not configured. See README for setup instructions." HTTP status 403 (Forbidden), since this is a permanent configuration issue, not a temporary outage.

### Implementation Details

- Add `username`, `password`, and `auth_strategy` attributes to `CompletionKit::Configuration`
- Add `before_action :authenticate_completion_kit!` to `CompletionKit::ApplicationController`
- `authenticate_completion_kit!` checks mode and dispatches accordingly
- Add `CompletionKit::ConfigurationError` exception class
- Production block page is a simple ERB template, no layout dependency
- The `after_initialize` warning uses `Rails.logger.warn`

### Files to Create/Modify

- Modify: `lib/completion_kit.rb` — add config attributes
- Modify: `app/controllers/completion_kit/application_controller.rb` — add before_action
- Create: `app/views/completion_kit/errors/auth_required.html.erb` — production block page
- Modify: `lib/completion_kit/engine.rb` — add after_initialize warning
- Modify: `README.md` — document auth setup

---

## Part 2: Feature Audit

### 2A: Prompt Versioning & Public API

**What to verify:**

- `Prompt#publish!` sets `current: true` on the target version, `current: false` on all other family versions
- Publishing an older version (rollback) works: if v3 is current and you publish v1, v1 becomes current
- `CompletionKit.current_prompt("name")` returns the published (current) version
- `CompletionKit.current_prompt_payload("name")` returns the correct hash
- `CompletionKit.render_current_prompt("name", variables)` substitutes `{{variable}}` placeholders correctly
- `Prompt#clone_as_new_version` creates a new version with incremented version_number and `current: false`

**UI addition:**

- Add "Make current" button on the prompt show page for each non-current version in the version list
- Button submits a POST to the existing `publish` route via `button_to`
- The already-current version shows a "Current" badge instead of the button

### 2B: End-to-End Generation Pipeline

**What to verify (with Faraday-level HTTP stubs, not method mocks):**

- `Run#generate_responses!` with a dataset:
  - Parses CSV via `CsvProcessor`
  - For each row, substitutes variables into prompt template
  - Calls LLM API with the rendered prompt (verify request payload)
  - Creates `Response` record with correct `input_data` (JSON), `response_text`, `expected_output`
  - Sets run status to "generating" during, "completed" after (when no judge configured)

- `Run#generate_responses!` without a dataset:
  - Runs prompt template as-is (no substitution)
  - Creates single `Response` with `input_data: nil`

**Bug fix required:** `Response` model currently has `validates :input_data, presence: true`, which prevents no-dataset runs from saving. Remove this validation — `input_data` should allow nil for runs without a dataset.

- LLM client wiring:
  - `OpenAiClient` sends correct headers (`Authorization: Bearer ...`) and payload format
  - `AnthropicClient` sends correct headers (`x-api-key`, `anthropic-version`) and payload format
  - `LlamaClient` sends to configured endpoint with correct payload

### 2C: End-to-End Judging Pipeline

**What to verify (with Faraday-level HTTP stubs):**

- `Run#judge_responses!`:
  - Sets status to "judging"
  - For each response, for each metric in `criteria.ordered_metrics`:
    - `JudgeService` builds prompt with: response text, expected output, original prompt, metric criteria, evaluation steps, rubric text
    - Calls judge model via LLM client
    - Parses `Score: N` and `Feedback: ...` from response
    - Creates/updates `Review` with `ai_score`, `ai_feedback`, `metric_id`, `metric_name`, `status: "evaluated"`
  - Sets status to "completed"

- Re-judging:
  - `find_or_initialize_by(metric_id)` updates existing reviews
  - No duplicate reviews created
  - Scores can change on re-judge

- Failure handling:
  - API error during generation sets status to "failed"
  - API error during judging sets status to "failed"
  - Error message added to `run.errors` (transient, available on the current object instance only — not persisted to the database)

### 2D: Status Transitions

**Verify these state flows:**

- Happy path with judge: pending → generating → judging → completed
- Happy path without judge: pending → generating → completed
- Generation failure: pending → generating → failed
- Judging failure: pending → generating → judging → failed

### 2E: Results & Scoring

**What to verify:**

- `Response#score` returns average of review `ai_score` values
- `Response#reviewed?` returns true when reviews with scores exist
- `Run#avg_score` returns average across all responses
- `Run#metric_averages` returns per-metric averages
- Show page sorting: default sort for judged runs is score descending; `sort=score_asc` explicitly orders lowest first

### 2F: README Update

Add an "Authentication" section to README covering:

- Basic auth configuration example (with env var in the block)
- Custom auth hook example (Devise)
- Production requirement explanation
- Example initializer file

---

## Out of Scope

- Background job processing (generation/judging remain synchronous)
- Pagination
- Multi-tenancy
- Export functionality
- MCP server (saved as separate future idea)
