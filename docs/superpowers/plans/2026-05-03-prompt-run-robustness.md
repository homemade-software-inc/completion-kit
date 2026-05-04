# Prompt Run Robustness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch from `:async` to Solid Queue, fan out each prompt run into per-row LLM jobs that retry independently, surface provider failures clearly, and let users retry only the failed rows.

**Architecture:** Engine ships row-level jobs (`GenerateRowJob`, `JudgeReviewJob`, `RunCompletionCheckJob`) with Solid Queue concurrency keys (per-provider + per-run). Generation and judging interleave — each `GenerateRowJob` enqueues its own `JudgeReviewJob`s on success. Run completion is detected by a tiny check job serialized through a per-run concurrency lock. UI status header shows two counters; failed rows surface provider-named badges with a per-run "retry failed rows" action.

**Tech Stack:** Rails 7 engine, Solid Queue (Active Job adapter), Turbo Streams, RSpec + FactoryBot, SQLite for tests / Postgres (Supabase) for prod.

**Spec:** `docs/superpowers/specs/2026-05-01-prompt-run-robustness-design.md`

---

## Conventions used in every task

- **Test path mirrors source path.** A model at `app/models/completion_kit/foo.rb` has its spec at `spec/models/completion_kit/foo_spec.rb`. A job at `app/jobs/completion_kit/foo_job.rb` has its spec at `spec/jobs/completion_kit/foo_job_spec.rb`.
- **Test database is in-memory SQLite** — its schema is hand-written in `spec/rails_helper.rb` (lines ~40–170). Any column added to a real migration MUST also be added to that schema or the spec database won't have it.
- **Run-spec broadcasts are stubbed** at the top of `spec/models/completion_kit/run_spec.rb` to avoid Action Cable noise. Follow the same pattern for any spec that exercises a method that broadcasts.
- **Factories** live in `spec/factories/`, named `completion_kit_<model>`, e.g. `create(:completion_kit_run)`.
- **Run all specs:** `bundle exec rspec`. Run one file: `bundle exec rspec spec/models/completion_kit/run_spec.rb`. Run one example: append `:LINE`.
- **No comments in code** (project-wide rule from `CLAUDE.md`). The plan never asks you to add code comments.
- **Commit messages** are subject-line only or subject + one short sentence. No multi-paragraph bodies. Do not include AI attribution.

---

# Phase 1 (PR 1): Schema + status backfill

> Goal of this PR: land all schema additions and backfill existing rows to terminal states. No behavior change. Safe to ship to web alone.

---

### Task 1: Add status + error columns to completion_kit_responses

**Files:**
- Create: `db/migrate/<timestamp>_add_status_and_error_to_responses.rb`
- Modify: `spec/rails_helper.rb` (in-memory schema, find the `create_table :completion_kit_responses` block ~line 119)
- Modify: `app/models/completion_kit/response.rb`
- Modify: `spec/factories/responses.rb`
- Test: `spec/models/completion_kit/response_spec.rb`

- [ ] **Step 1: Generate the engine migration**

Run: `bundle exec rails g migration AddStatusAndErrorToResponses --no-test-framework`

This creates a file under `db/migrate/`. Rename the timestamp portion to today's date if needed.

- [ ] **Step 2: Fill the migration**

```ruby
class AddStatusAndErrorToResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_responses, :status, :string, default: "pending", null: false
    add_column :completion_kit_responses, :error_provider, :string
    add_column :completion_kit_responses, :error_class, :string
    add_column :completion_kit_responses, :error_status, :integer
    add_column :completion_kit_responses, :error_message, :text
    add_column :completion_kit_responses, :attempts, :integer, default: 0, null: false
    add_column :completion_kit_responses, :row_index, :integer
    add_index  :completion_kit_responses, [:run_id, :status]

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_responses
          SET status = 'succeeded'
          WHERE response_text IS NOT NULL AND length(response_text) > 0
        SQL
      end
    end
  end
end
```

- [ ] **Step 3: Mirror the columns in the in-memory test schema**

In `spec/rails_helper.rb`, find the `create_table :completion_kit_responses` block and add the columns:

```ruby
create_table :completion_kit_responses, force: true do |t|
  t.references :run, null: false
  t.text :input_data
  t.text :response_text
  t.text :expected_output
  t.string :status, default: "pending", null: false
  t.string :error_provider
  t.string :error_class
  t.integer :error_status
  t.text :error_message
  t.integer :attempts, default: 0, null: false
  t.integer :row_index
  t.index [:run_id, :status]
  t.timestamps
end
```

- [ ] **Step 4: Write a failing test for the Response status enum + terminal? predicate**

Append to `spec/models/completion_kit/response_spec.rb`:

```ruby
RSpec.describe CompletionKit::Response, type: :model do
  describe "status" do
    it "defaults to pending on a new record" do
      response = build(:completion_kit_response, status: nil, response_text: "anything")
      response.valid?
      expect(response.status).to eq("pending")
    end

    it "validates inclusion in the STATUSES list" do
      response = build(:completion_kit_response, status: "weird")
      expect(response).not_to be_valid
      expect(response.errors[:status]).to be_present
    end

    %w[pending retrying].each do |status|
      it "is not terminal? when status is #{status}" do
        expect(build(:completion_kit_response, status: status)).not_to be_terminal
      end
    end

    %w[succeeded failed].each do |status|
      it "is terminal? when status is #{status}" do
        expect(build(:completion_kit_response, status: status)).to be_terminal
      end
    end
  end
end
```

- [ ] **Step 5: Run tests — confirm they fail**

Run: `bundle exec rspec spec/models/completion_kit/response_spec.rb`
Expected: failures on the new examples (`status` returns nil OR predicate `terminal?` undefined).

- [ ] **Step 6: Implement the validation and predicate on the model**

In `app/models/completion_kit/response.rb`:

```ruby
module CompletionKit
  class Response < ApplicationRecord
    STATUSES = %w[pending retrying succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    belongs_to :run
    has_many :reviews, dependent: :destroy

    delegate :prompt, to: :run

    validates :response_text, presence: true, if: :requires_response_text?
    validates :status, inclusion: { in: STATUSES }

    before_validation :set_default_status, on: :create

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def as_json(options = {})
      {
        id: id, run_id: run_id, input_data: input_data,
        response_text: response_text, expected_output: expected_output,
        created_at: created_at, score: score, reviewed: reviewed?,
        reviews: reviews.map(&:as_json),
        status: status, attempts: attempts, row_index: row_index,
        error: error_payload
      }
    end

    def score
      scores = reviews.select { |r| r.ai_score.present? }.map { |r| r.ai_score.to_f }
      return nil if scores.empty?

      (scores.sum / scores.length).round(2)
    end

    def reviewed?
      reviews.any? { |r| r.ai_score.present? }
    end

    def error_payload
      return nil if error_class.blank?
      { provider: error_provider, class: error_class, status: error_status, message: error_message }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end

    def requires_response_text?
      status == "succeeded"
    end
  end
end
```

- [ ] **Step 7: Update the response factory so existing tests still pass**

In `spec/factories/responses.rb`:

```ruby
FactoryBot.define do
  factory :completion_kit_response, class: "CompletionKit::Response" do
    association :run, factory: :completion_kit_run
    input_data { { content: "Release notes", audience: "developers" }.to_json }
    response_text { "A generated summary" }
    expected_output { "A developer-focused summary" }
    status { "succeeded" }

    trait :pending do
      status { "pending" }
      response_text { nil }
    end

    trait :failed do
      status { "failed" }
      response_text { nil }
      error_provider { "openai" }
      error_class { "Faraday::TimeoutError" }
      error_status { nil }
      error_message { "execution expired" }
      attempts { 5 }
    end
  end
end
```

(The default `status: "succeeded"` keeps existing specs that don't care about status passing because `response_text` is also present.)

- [ ] **Step 8: Run tests — confirm green**

Run: `bundle exec rspec spec/models/completion_kit/response_spec.rb`
Expected: all examples pass.

- [ ] **Step 9: Commit**

```bash
git add db/migrate spec/rails_helper.rb app/models/completion_kit/response.rb spec/factories/responses.rb spec/models/completion_kit/response_spec.rb
git commit -m "add status and error columns to responses"
```

---

### Task 2: Add status + error columns to completion_kit_reviews

**Files:**
- Create: `db/migrate/<timestamp>_add_status_and_error_to_reviews.rb`
- Modify: `spec/rails_helper.rb` (the `create_table :completion_kit_reviews` block ~line 132)
- Modify: `app/models/completion_kit/review.rb`
- Modify: `spec/factories/reviews.rb`
- Test: `spec/models/completion_kit/review_spec.rb` (create if missing)

- [ ] **Step 1: Generate the migration**

Run: `bundle exec rails g migration AddStatusAndErrorToReviews --no-test-framework`

- [ ] **Step 2: Fill the migration**

```ruby
class AddStatusAndErrorToReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_reviews, :error_provider, :string
    add_column :completion_kit_reviews, :error_class, :string
    add_column :completion_kit_reviews, :error_status, :integer
    add_column :completion_kit_reviews, :error_message, :text
    add_column :completion_kit_reviews, :attempts, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_reviews
          SET status = 'succeeded'
          WHERE ai_score IS NOT NULL
        SQL
      end
    end
  end
end
```

(The `status` column already exists on reviews — the existing `STATUSES` was `pending evaluated failed`. We are renaming `evaluated` → `succeeded` for consistency and adding `retrying`.)

- [ ] **Step 2b: Create the concurrent index migration**

Create a second migration `db/migrate/<timestamp+1>_index_reviews_on_response_id_and_status.rb`:

```ruby
class IndexReviewsOnResponseIdAndStatus < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :completion_kit_reviews, [:response_id, :status],
              algorithm: :concurrently,
              if_not_exists: true
  end
end
```

Same reasoning as Task 1: `add_index` on Postgres takes `ACCESS EXCLUSIVE` and blocks reads/writes; concurrent index needs its own non-transactional migration.

- [ ] **Step 3: Backfill the existing `evaluated` rows in the migration too**

Append to the `dir.up` block:

```ruby
execute <<~SQL
  UPDATE completion_kit_reviews
  SET status = 'succeeded'
  WHERE status = 'evaluated'
SQL
```

- [ ] **Step 4: Mirror new columns in the in-memory schema**

In `spec/rails_helper.rb`, find the `create_table :completion_kit_reviews` block and add the new columns:

```ruby
create_table :completion_kit_reviews, force: true do |t|
  t.references :response, null: false
  t.references :metric
  t.string :metric_name
  t.text :instruction
  t.string :status
  t.decimal :ai_score, precision: 4, scale: 1
  t.text :ai_feedback
  t.string :error_provider
  t.string :error_class
  t.integer :error_status
  t.text :error_message
  t.integer :attempts, default: 0, null: false
  t.index [:response_id, :status]
  t.timestamps
end
```

- [ ] **Step 5: Write failing test for new STATUSES + terminal?**

Create `spec/models/completion_kit/review_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::Review, type: :model do
  describe "status" do
    let(:response) { create(:completion_kit_response) }

    it "validates inclusion in pending/retrying/succeeded/failed" do
      review = build(:completion_kit_review, response: response, status: "evaluated")
      expect(review).not_to be_valid
    end

    %w[pending retrying].each do |status|
      it "is not terminal? when status is #{status}" do
        expect(build(:completion_kit_review, response: response, status: status)).not_to be_terminal
      end
    end

    %w[succeeded failed].each do |status|
      it "is terminal? when status is #{status}" do
        expect(build(:completion_kit_review, response: response, status: status)).to be_terminal
      end
    end
  end
end
```

- [ ] **Step 6: Run tests — confirm they fail**

Run: `bundle exec rspec spec/models/completion_kit/review_spec.rb`
Expected: failures (no `terminal?` method, `evaluated` still accepted).

- [ ] **Step 7: Update the Review model**

In `app/models/completion_kit/review.rb`:

```ruby
module CompletionKit
  class Review < ApplicationRecord
    STATUSES = %w[pending retrying succeeded failed].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    belongs_to :response
    belongs_to :metric, optional: true

    validates :metric_name, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :ai_score, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 5 }, allow_nil: true

    before_validation :set_default_status

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def error_payload
      return nil if error_class.blank?
      { provider: error_provider, class: error_class, status: error_status, message: error_message }
    end

    def as_json(options = {})
      {
        id: id, response_id: response_id, metric_id: metric_id,
        metric_name: metric_name, ai_score: ai_score,
        ai_feedback: ai_feedback, status: status, attempts: attempts,
        error: error_payload
      }
    end

    private

    def set_default_status
      self.status ||= "pending"
    end
  end
end
```

- [ ] **Step 8: Update the review factory**

In `spec/factories/reviews.rb`, replace the contents with:

```ruby
FactoryBot.define do
  factory :completion_kit_review, class: "CompletionKit::Review" do
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_name { "Quality" }
    instruction { "Rate the response quality." }
    status { "succeeded" }
    ai_score { 4.0 }
    ai_feedback { "Good response." }
  end
end
```

- [ ] **Step 9: Find anywhere in the codebase that writes `status: "evaluated"` and update**

Run: `grep -rn '"evaluated"' app/ spec/`

In `app/models/completion_kit/run.rb` `judge_responses!` method (around line 132–138), change the `status: "evaluated"` literal in the `assign_attributes` block to `status: "succeeded"`. (This method will be replaced entirely in Phase 2 but must not break in the interim.)

- [ ] **Step 10: Run tests — confirm green**

Run: `bundle exec rspec spec/models/completion_kit/review_spec.rb spec/models/completion_kit/run_spec.rb`
Expected: all examples pass.

- [ ] **Step 11: Commit**

```bash
git add db/migrate spec/rails_helper.rb app/models/completion_kit/review.rb app/models/completion_kit/run.rb spec/factories/reviews.rb spec/models/completion_kit/review_spec.rb
git commit -m "add error columns to reviews and unify status to succeeded"
```

---

### Task 3: Collapse Run status enum and add failure_summary

**Files:**
- Create: `db/migrate/<timestamp>_collapse_run_status_and_add_failure_summary.rb`
- Modify: `spec/rails_helper.rb` (the `create_table :completion_kit_runs` block ~line 96)
- Modify: `app/models/completion_kit/run.rb`
- Test: `spec/models/completion_kit/run_spec.rb`

- [ ] **Step 1: Generate the migration**

Run: `bundle exec rails g migration CollapseRunStatusAndAddFailureSummary --no-test-framework`

- [ ] **Step 2: Fill the migration**

```ruby
class CollapseRunStatusAndAddFailureSummary < ActiveRecord::Migration[7.1]
  def change
    add_column :completion_kit_runs, :failure_summary, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE completion_kit_runs
          SET status = 'running'
          WHERE status IN ('generating', 'judging')
        SQL
      end
    end
  end
end
```

- [ ] **Step 3: Mirror failure_summary in the in-memory schema**

In `spec/rails_helper.rb`, in the `create_table :completion_kit_runs` block, add `t.string :failure_summary`.

- [ ] **Step 4: Write failing test for the collapsed enum**

In `spec/models/completion_kit/run_spec.rb`, append:

```ruby
describe "status enum" do
  it "rejects the legacy generating status" do
    run = build(:completion_kit_run, status: "generating")
    expect(run).not_to be_valid
  end

  it "rejects the legacy judging status" do
    run = build(:completion_kit_run, status: "judging")
    expect(run).not_to be_valid
  end

  it "accepts running" do
    run = build(:completion_kit_run, status: "running")
    expect(run).to be_valid
  end
end
```

- [ ] **Step 5: Run tests — confirm they fail**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -e "status enum"`
Expected: examples fail (current STATUSES still includes generating/judging).

- [ ] **Step 6: Update STATUSES on Run**

In `app/models/completion_kit/run.rb`:

```ruby
STATUSES = %w[pending running completed failed].freeze
```

(Leave the existing `generate_responses!` / `judge_responses!` methods alone for now — they will be rewritten in Phase 2. Their `update!(status: "generating", ...)` and `update!(status: "judging", ...)` calls will fail validation, but that is intentional: those code paths must not be invoked between this PR and the Phase 2 PR. The `:async` adapter is still in effect, so existing controller actions still call those methods.)

To avoid breaking the existing flow during the in-between window, change the literal status writes in `generate_responses!` and `judge_responses!` to write `"running"` instead of `"generating"` or `"judging"`. The methods otherwise stay intact:

```ruby
update!(status: "running", progress_current: 0, progress_total: rows.length, error_message: nil)
```

```ruby
update!(status: "running", progress_current: 0, progress_total: total_evaluations, error_message: nil)
```

- [ ] **Step 7: Run the existing run spec**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb`
Expected: all green. (Any spec that expected status "generating"/"judging" must be updated to expect "running".)

- [ ] **Step 8: Commit**

```bash
git add db/migrate spec/rails_helper.rb app/models/completion_kit/run.rb spec/models/completion_kit/run_spec.rb
git commit -m "collapse run status to pending/running/completed/failed"
```

---

### Task 4: Install engine migrations into the standalone app

**Files:**
- Run rake task that copies engine migrations into `standalone/db/migrate/`

- [ ] **Step 1: Install engine migrations**

Run: `cd standalone && bin/rails completion_kit:install:migrations`

This copies the three new migrations from `db/migrate/` into `standalone/db/migrate/<timestamp>_*.completion_kit.rb`.

- [ ] **Step 2: Run them locally**

Run: `cd standalone && bin/rails db:migrate`

- [ ] **Step 3: Confirm schema.rb updated**

Run: `git diff standalone/db/schema.rb`

You should see the new columns on `completion_kit_responses`, `completion_kit_reviews`, `completion_kit_runs`.

- [ ] **Step 4: Commit the installed migrations + schema change**

```bash
git add standalone/db/migrate standalone/db/schema.rb
git commit -m "install schema migrations into standalone"
```

> **PR 1 ends here.** Open the PR with the four task commits. CI must be green. After merge, Render's pre-deploy `db:migrate` runs the migrations on Supabase. No behavior change yet.

---

# Phase 2 (PR 2): Adapter switch + new jobs

> Goal of this PR: install Solid Queue, replace the monolithic generation/judging methods with row-level jobs, and switch the queue adapter. **The Render Worker service must exist before merging this PR** — the `:async` adapter goes away the moment this ships.

---

### Task 5: Add solid_queue gem to standalone

**Files:**
- Modify: `standalone/Gemfile`

- [ ] **Step 1: Add the gem**

In `standalone/Gemfile`, after `gem "completion-kit", path: "../"`:

```ruby
gem "solid_queue"
gem "mission_control-jobs"
```

- [ ] **Step 2: Install**

Run: `cd standalone && bundle install`

- [ ] **Step 3: Verify the gems landed in the lockfile**

Run: `grep -E "(solid_queue|mission_control-jobs) " standalone/Gemfile.lock`
Expected: both names appear with versions.

- [ ] **Step 4: Commit**

```bash
git add standalone/Gemfile standalone/Gemfile.lock
git commit -m "install solid_queue and mission_control-jobs in standalone"
```

---

### Task 6: Add config/queue.yml in the standalone

**Files:**
- Create: `standalone/config/queue.yml`

- [ ] **Step 1: Write the config**

Create `standalone/config/queue.yml`:

```yaml
default: &default
  dispatchers:
    - polling_interval: 1
      batch_size: 500
  workers:
    - queues: [llm, default]
      threads: <%= ENV.fetch("SOLID_QUEUE_THREADS", 10) %>
      processes: <%= ENV.fetch("SOLID_QUEUE_PROCESSES", 1) %>
      polling_interval: 0.5

development:
  <<: *default

test:
  <<: *default

production:
  <<: *default
```

- [ ] **Step 2: Commit**

```bash
git add standalone/config/queue.yml
git commit -m "add solid_queue worker config"
```

---

### Task 7: Add Prompt#llm_model_provider helper

**Files:**
- Modify: `app/models/completion_kit/prompt.rb`
- Modify: `spec/models/completion_kit/prompt_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/models/completion_kit/prompt_spec.rb`:

```ruby
describe "#llm_model_provider" do
  it "returns openai for a gpt-4 model" do
    prompt = build(:completion_kit_prompt, llm_model: "gpt-4o")
    expect(prompt.llm_model_provider).to eq("openai")
  end

  it "returns anthropic for a claude-3 model" do
    prompt = build(:completion_kit_prompt, llm_model: "claude-3-5-sonnet-20241022")
    expect(prompt.llm_model_provider).to eq("anthropic")
  end

  it "returns nil for an unknown model" do
    prompt = build(:completion_kit_prompt, llm_model: "totally-made-up-model")
    expect(prompt.llm_model_provider).to be_nil
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

Run: `bundle exec rspec spec/models/completion_kit/prompt_spec.rb -e "llm_model_provider"`
Expected: NoMethodError.

- [ ] **Step 3: Implement**

In `app/models/completion_kit/prompt.rb`, add (after `display_name`):

```ruby
def llm_model_provider
  ApiConfig.provider_for_model(llm_model)
end
```

- [ ] **Step 4: Run tests — confirm green**

Run: `bundle exec rspec spec/models/completion_kit/prompt_spec.rb -e "llm_model_provider"`

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/prompt.rb spec/models/completion_kit/prompt_spec.rb
git commit -m "add Prompt#llm_model_provider helper"
```

---

### Task 8: Add CompletionKit::RateLimitError exception

**Files:**
- Create: `lib/completion_kit/errors.rb`
- Modify: `lib/completion_kit.rb` (require the new file)
- Test: `spec/lib/completion_kit/errors_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/lib/completion_kit/errors_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::RateLimitError do
  it "carries provider, status, and retry_after attributes" do
    error = described_class.new("rate limited", provider: "openai", status: 429, retry_after: 30)
    expect(error.message).to eq("rate limited")
    expect(error.provider).to eq("openai")
    expect(error.status).to eq(429)
    expect(error.retry_after).to eq(30)
  end

  it "subclasses StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end
end

RSpec.describe CompletionKit::ConfigurationError do
  it "subclasses StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end
end
```

- [ ] **Step 2: Run tests — confirm they fail**

Run: `bundle exec rspec spec/lib/completion_kit/errors_spec.rb`
Expected: NameError (`uninitialized constant CompletionKit::RateLimitError`).

- [ ] **Step 3: Create the errors file**

Create `lib/completion_kit/errors.rb`:

```ruby
module CompletionKit
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class RateLimitError < Error
    attr_reader :provider, :status, :retry_after

    def initialize(message = nil, provider: nil, status: nil, retry_after: nil)
      super(message)
      @provider = provider
      @status = status
      @retry_after = retry_after
    end
  end
end
```

- [ ] **Step 4: Require it from lib/completion_kit.rb**

Open `lib/completion_kit.rb` and add `require "completion_kit/errors"` near the top with the other requires.

- [ ] **Step 5: Run tests — confirm green**

Run: `bundle exec rspec spec/lib/completion_kit/errors_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add lib/completion_kit/errors.rb lib/completion_kit.rb spec/lib/completion_kit/errors_spec.rb
git commit -m "add RateLimitError and ConfigurationError exception classes"
```

---

### Task 9: Make LlmClient subclasses raise RateLimitError on 429

**Files:**
- Modify: each LlmClient subclass under `app/services/completion_kit/` — `openai_client.rb`, `anthropic_client.rb`, `ollama_client.rb`, `openrouter_client.rb`
- Test: a spec for each subclass under `spec/services/completion_kit/` (create if missing)

- [ ] **Step 1: List the subclasses**

Run: `ls app/services/completion_kit/*_client.rb`

You should see at least openai, anthropic, ollama, openrouter clients. For each, repeat steps 2–4.

- [ ] **Step 2: Write the failing test (using OpenAiClient as the template)**

Create or append `spec/services/completion_kit/openai_client_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::OpenAiClient do
  let(:client) { described_class.new(api_key: "sk-test") }

  describe "#generate_completion" do
    it "raises RateLimitError when the API returns 429" do
      stub = Faraday::Adapter::Test::Stubs.new do |s|
        s.post("/v1/chat/completions") { [429, { "Retry-After" => "30" }, '{"error":{"message":"rate limit"}}'] }
      end
      conn = Faraday.new { |b| b.adapter :test, stub }
      allow(client).to receive(:build_connection).and_return(conn)

      expect {
        client.generate_completion("hi", model: "gpt-4o")
      }.to raise_error(CompletionKit::RateLimitError) do |error|
        expect(error.provider).to eq("openai")
        expect(error.status).to eq(429)
        expect(error.retry_after).to eq(30)
      end
    end
  end
end
```

- [ ] **Step 3: Run the test — confirm it fails**

Run: `bundle exec rspec spec/services/completion_kit/openai_client_spec.rb`
Expected: failure (no rate-limit handling raises a different error or returns a value).

- [ ] **Step 4: Update the client**

In `app/services/completion_kit/openai_client.rb`, after the response is received and before parsing the body, add:

```ruby
if response.status == 429
  raise CompletionKit::RateLimitError.new(
    extract_message(response.body) || "Rate limit",
    provider: "openai",
    status: 429,
    retry_after: response.headers["Retry-After"]&.to_i
  )
end
```

(`extract_message` is the existing helper used by the client; if it doesn't exist, just pass `response.body.to_s.truncate(500)`.)

- [ ] **Step 5: Run the test — confirm green**

Run: `bundle exec rspec spec/services/completion_kit/openai_client_spec.rb`

- [ ] **Step 6: Repeat steps 2–5 for each other client**

For `AnthropicClient`, `OllamaClient`, `OpenRouterClient`: write the same shape of test against the provider's endpoint, raise `RateLimitError.new(..., provider: "anthropic"|"ollama"|"openrouter", status: 429, ...)`. Anthropic uses the `anthropic-ratelimit-requests-reset` header; OpenAI uses `Retry-After`. If the provider doesn't expose a retry-after, pass `nil` and the job's fixed-step backoff covers it.

- [ ] **Step 7: Run all client specs together**

Run: `bundle exec rspec spec/services/completion_kit`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
git add app/services/completion_kit spec/services/completion_kit
git commit -m "raise RateLimitError on 429 across all LLM clients"
```

---

### Task 10: Create GenerateRowJob with retries and concurrency

**Files:**
- Create: `app/jobs/completion_kit/generate_row_job.rb`
- Test: `spec/jobs/completion_kit/generate_row_job_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/jobs/completion_kit/generate_row_job_spec.rb`:

```ruby
require "rails_helper"
require "faraday"

RSpec.describe CompletionKit::GenerateRowJob, type: :job do
  let(:run) { create(:completion_kit_run) }
  let(:response) { run.responses.create!(status: "pending", row_index: 0, response_text: nil) }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "calls the LLM client and marks the response succeeded" do
    fake_client = double("client", generate_completion: "the answer", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    described_class.perform_now(run.id, response.id)

    response.reload
    expect(response.status).to eq("succeeded")
    expect(response.response_text).to eq("the answer")
    expect(response.error_class).to be_nil
  end

  it "records terminal failure context after exhaustion of retries" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(
      CompletionKit::RateLimitError.new("over budget", provider: "openai", status: 429)
    )

    expect {
      described_class.perform_now(run.id, response.id)
    }.not_to raise_error

    response.reload
    expect(response.status).to eq("failed")
    expect(response.error_provider).to eq("openai")
    expect(response.error_status).to eq(429)
    expect(response.error_class).to eq("CompletionKit::RateLimitError")
    expect(response.error_message).to include("over budget")
  end

  it "enqueues a JudgeReviewJob per metric on success" do
    metric = create(:completion_kit_metric)
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)

    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)
    allow(run).to receive(:judge_configured?).and_return(true)
    allow(CompletionKit::Run).to receive(:find).with(run.id).and_return(run)

    expect(CompletionKit::JudgeReviewJob).to receive(:perform_later).with(response.id, metric.id)

    described_class.perform_now(run.id, response.id)
  end

  it "enqueues RunCompletionCheckJob at the end" do
    fake_client = double("client", generate_completion: "ok", configured?: true)
    allow(CompletionKit::LlmClient).to receive(:for_model).and_return(fake_client)

    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    described_class.perform_now(run.id, response.id)
  end
end
```

- [ ] **Step 2: Run the test — confirm it fails**

Run: `bundle exec rspec spec/jobs/completion_kit/generate_row_job_spec.rb`
Expected: NameError (job class doesn't exist).

- [ ] **Step 3: Implement the job**

Create `app/jobs/completion_kit/generate_row_job.rb`:

```ruby
module CompletionKit
  class GenerateRowJob < ApplicationJob
    queue_as :llm

    retry_on Faraday::TimeoutError,
             Faraday::ConnectionFailed,
             wait: :polynomially_longer, attempts: 5

    retry_on CompletionKit::RateLimitError,
             wait: ->(executions) { 30 * executions }, attempts: 5

    discard_on ActiveJob::DeserializationError
    discard_on CompletionKit::ConfigurationError

    rescue_from(StandardError) do |error|
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    before_perform do |job|
      response = Response.find_by(id: job.arguments.last)
      next unless response
      response.update_columns(status: "retrying", attempts: response.attempts + 1)
      response.run.send(:broadcast_response_update, response) if response.run
    end

    def perform(run_id, response_id)
      @run_id = run_id
      @response_id = response_id

      response = Response.find(response_id)
      run = response.run
      prompt = run.prompt

      row = parsed_input(response)
      rendered = CsvProcessor.apply_variables(prompt, row)
      client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

      raise ConfigurationError, client.configuration_errors.join(", ") unless client.configured?

      text = client.generate_completion(rendered, model: prompt.llm_model, temperature: run.temperature)

      response.update!(
        status: "succeeded",
        response_text: text,
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )
      run.send(:broadcast_response_update, response)

      if run.judge_configured?
        run.metrics.each do |metric|
          JudgeReviewJob.perform_later(response.id, metric.id)
        end
      end

      enqueue_completion_check
    end

    private

    def parsed_input(response)
      return {} if response.input_data.blank?
      JSON.parse(response.input_data)
    rescue JSON::ParserError
      {}
    end

    def record_terminal_failure!(error)
      response = Response.find_by(id: @response_id)
      return unless response

      response.update_columns(
        status: "failed",
        error_provider: provider_for(response),
        error_class: error.class.name,
        error_status: error.respond_to?(:status) ? error.status : nil,
        error_message: error.message.to_s.truncate(2000)
      )
      response.run&.send(:broadcast_response_update, response)
    end

    def provider_for(response)
      response.run&.prompt&.llm_model_provider
    end

    def enqueue_completion_check
      RunCompletionCheckJob.perform_later(@run_id)
    end
  end
end
```

- [ ] **Step 4: Run the test — confirm green**

Run: `bundle exec rspec spec/jobs/completion_kit/generate_row_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add app/jobs/completion_kit/generate_row_job.rb spec/jobs/completion_kit/generate_row_job_spec.rb
git commit -m "add GenerateRowJob with retries and per-row failure capture"
```

---

### Task 11: Create JudgeReviewJob

**Files:**
- Create: `app/jobs/completion_kit/judge_review_job.rb`
- Test: `spec/jobs/completion_kit/judge_review_job_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/jobs/completion_kit/judge_review_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::JudgeReviewJob, type: :job do
  let(:run) { create(:completion_kit_run, judge_model: "gpt-4o") }
  let(:metric) { create(:completion_kit_metric, name: "Quality") }
  let(:response) { create(:completion_kit_response, run: run, response_text: "answer") }

  before do
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
    allow(CompletionKit::RunCompletionCheckJob).to receive(:perform_later)
  end

  it "evaluates and creates/updates a Review with succeeded status" do
    fake_judge = double("judge")
    allow(fake_judge).to receive(:evaluate).and_return(score: 4, feedback: "good")
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    described_class.perform_now(response.id, metric.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("succeeded")
    expect(review.ai_score).to eq(4)
    expect(review.ai_feedback).to eq("good")
  end

  it "records failure context on terminal failure" do
    allow_any_instance_of(described_class).to receive(:perform).and_raise(
      CompletionKit::RateLimitError.new("limit", provider: "anthropic", status: 429)
    )

    described_class.perform_now(response.id, metric.id)

    review = response.reviews.find_by(metric_id: metric.id)
    expect(review.status).to eq("failed")
    expect(review.error_provider).to eq("anthropic")
    expect(review.error_status).to eq(429)
  end

  it "enqueues RunCompletionCheckJob" do
    fake_judge = double("judge", evaluate: { score: 4, feedback: "ok" })
    allow(CompletionKit::JudgeService).to receive(:new).and_return(fake_judge)
    allow(CompletionKit::ApiConfig).to receive(:for_model).and_return({})

    expect(CompletionKit::RunCompletionCheckJob).to receive(:perform_later).with(run.id)

    described_class.perform_now(response.id, metric.id)
  end
end
```

- [ ] **Step 2: Run the test — confirm it fails**

Run: `bundle exec rspec spec/jobs/completion_kit/judge_review_job_spec.rb`
Expected: NameError.

- [ ] **Step 3: Implement the job**

Create `app/jobs/completion_kit/judge_review_job.rb`:

```ruby
module CompletionKit
  class JudgeReviewJob < ApplicationJob
    queue_as :llm

    retry_on Faraday::TimeoutError,
             Faraday::ConnectionFailed,
             wait: :polynomially_longer, attempts: 5

    retry_on CompletionKit::RateLimitError,
             wait: ->(executions) { 30 * executions }, attempts: 5

    discard_on ActiveJob::DeserializationError
    discard_on CompletionKit::ConfigurationError

    rescue_from(StandardError) do |error|
      record_terminal_failure!(error)
      enqueue_completion_check
    end

    before_perform do |job|
      response_id, metric_id = job.arguments
      review = find_or_init_review(response_id, metric_id)
      review.attempts = (review.attempts || 0) + 1
      review.status = "retrying"
      review.save!(validate: false)
      review.response.run.send(:broadcast_response_update, review.response) if review.response&.run
    end

    def perform(response_id, metric_id)
      @response_id = response_id
      @metric_id = metric_id

      response = Response.find(response_id)
      metric = Metric.find(metric_id)
      run = response.run

      judge = JudgeService.new(ApiConfig.for_model(run.judge_model).merge(judge_model: run.judge_model))
      evaluation = judge.evaluate(
        response.response_text,
        response.expected_output,
        run.prompt.template,
        criteria: metric.instruction.to_s,
        rubric_text: metric.display_rubric_text,
        input_data: response.input_data
      )

      review = response.reviews.find_or_initialize_by(metric_id: metric.id)
      review.assign_attributes(
        metric_name: metric.name,
        instruction: metric.instruction.to_s,
        status: "succeeded",
        ai_score: evaluation[:score],
        ai_feedback: evaluation[:feedback],
        error_provider: nil, error_class: nil, error_status: nil, error_message: nil
      )
      review.save!

      run.send(:broadcast_response_update, response)
      enqueue_completion_check
    end

    private

    def find_or_init_review(response_id, metric_id)
      Response.find(response_id).reviews.find_or_initialize_by(metric_id: metric_id).tap do |r|
        r.metric_name ||= Metric.find(metric_id).name
      end
    end

    def record_terminal_failure!(error)
      response = Response.find_by(id: @response_id)
      return unless response
      review = response.reviews.find_or_initialize_by(metric_id: @metric_id)
      review.assign_attributes(
        metric_name: review.metric_name || Metric.find_by(id: @metric_id)&.name || "(deleted metric)",
        status: "failed",
        error_provider: response.run&.judge_model && ApiConfig.provider_for_model(response.run.judge_model),
        error_class: error.class.name,
        error_status: error.respond_to?(:status) ? error.status : nil,
        error_message: error.message.to_s.truncate(2000)
      )
      review.save!(validate: false)
      response.run&.send(:broadcast_response_update, response)
    end

    def enqueue_completion_check
      response = Response.find_by(id: @response_id)
      RunCompletionCheckJob.perform_later(response.run_id) if response
    end
  end
end
```

- [ ] **Step 4: Run the test — confirm green**

Run: `bundle exec rspec spec/jobs/completion_kit/judge_review_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add app/jobs/completion_kit/judge_review_job.rb spec/jobs/completion_kit/judge_review_job_spec.rb
git commit -m "add JudgeReviewJob with per-review retries and failure capture"
```

---

### Task 12: Create RunCompletionCheckJob

**Files:**
- Create: `app/jobs/completion_kit/run_completion_check_job.rb`
- Test: `spec/jobs/completion_kit/run_completion_check_job_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/jobs/completion_kit/run_completion_check_job_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::RunCompletionCheckJob, type: :job do
  let(:run) { create(:completion_kit_run, status: "running") }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_sort_toolbar)
  end

  it "marks run completed when no responses are outstanding" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("completed")
  end

  it "leaves run as running when at least one response is non-terminal" do
    create(:completion_kit_response, run: run, status: "pending", response_text: nil)

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("running")
  end

  it "leaves run as running when at least one expected review is non-terminal" do
    metric = create(:completion_kit_metric)
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    response = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    response.reviews.create!(metric: metric, metric_name: metric.name, status: "pending")

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("running")
  end

  it "is a no-op when run is already completed" do
    run.update!(status: "completed")
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq("completed")
  end

  it "handles missing run gracefully" do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run — confirm it fails**

Run: `bundle exec rspec spec/jobs/completion_kit/run_completion_check_job_spec.rb`
Expected: NameError.

- [ ] **Step 3: Implement the job**

Create `app/jobs/completion_kit/run_completion_check_job.rb`:

```ruby
module CompletionKit
  class RunCompletionCheckJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      run = Run.find_by(id: run_id)
      return unless run
      return unless run.status == "running"
      return unless run.outstanding_work_zero?

      run.mark_completed!
    end
  end
end
```

- [ ] **Step 4: Run — confirm green**

Run: `bundle exec rspec spec/jobs/completion_kit/run_completion_check_job_spec.rb`

(The `outstanding_work_zero?` and `mark_completed!` methods on Run will be added in Task 13. The test will fail at this stage if those don't exist — proceed to Task 13 first if needed, then re-run this test, then commit Tasks 12 and 13 together.)

- [ ] **Step 5: Commit (after Task 13 lands)**

```bash
git add app/jobs/completion_kit/run_completion_check_job.rb spec/jobs/completion_kit/run_completion_check_job_spec.rb
git commit -m "add RunCompletionCheckJob"
```

---

### Task 13: Add Run#start!, #outstanding_work_zero?, #mark_completed!, #progress_snapshot

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Modify: `spec/models/completion_kit/run_spec.rb`

- [ ] **Step 1: Write the failing tests**

In `spec/models/completion_kit/run_spec.rb`, append:

```ruby
describe "#start!" do
  let(:dataset) do
    create(:completion_kit_dataset, csv_data: "content,audience\nrelease notes,devs\nfeature recap,pms\n")
  end
  let(:prompt) { create(:completion_kit_prompt, llm_model: "gpt-4o") }
  let(:run) { create(:completion_kit_run, prompt: prompt, dataset: dataset) }

  before do
    allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(true)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
  end

  it "creates one pending Response per dataset row with row_index set" do
    run.start!

    expect(run.responses.count).to eq(2)
    expect(run.responses.pluck(:status).uniq).to eq(["pending"])
    expect(run.responses.order(:row_index).pluck(:row_index)).to eq([0, 1])
  end

  it "enqueues a GenerateRowJob per row" do
    expect(CompletionKit::GenerateRowJob).to receive(:perform_later).twice
    run.start!
  end

  it "transitions to running and resets progress totals" do
    run.start!
    expect(run.reload.status).to eq("running")
    expect(run.progress_total).to eq(2)
    expect(run.progress_current).to eq(0)
  end

  it "fails with a configuration error when API isn't configured" do
    allow(CompletionKit::ApiConfig).to receive(:valid_for_model?).and_return(false)
    allow_any_instance_of(CompletionKit::LlmClient).to receive(:configuration_errors).and_return(["missing api key"])

    expect(run.start!).to be(false)
    expect(run.reload.status).to eq("failed")
    expect(run.failure_summary).to be_present
  end
end

describe "#outstanding_work_zero?" do
  let(:run) { create(:completion_kit_run) }

  it "returns true when all responses and reviews are terminal" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    expect(run.outstanding_work_zero?).to be true
  end

  it "returns false when any response is non-terminal" do
    create(:completion_kit_response, run: run, status: "pending", response_text: nil)
    expect(run.outstanding_work_zero?).to be false
  end

  it "returns false when any review is non-terminal" do
    metric = create(:completion_kit_metric)
    CompletionKit::RunMetric.create!(run: run, metric: metric, position: 1)
    response = create(:completion_kit_response, run: run, status: "succeeded", response_text: "ok")
    response.reviews.create!(metric: metric, metric_name: metric.name, status: "pending")
    expect(run.outstanding_work_zero?).to be false
  end
end

describe "#progress_snapshot" do
  let(:run) { create(:completion_kit_run) }

  it "returns counts for both gen and judge phases" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "a")
    create(:completion_kit_response, run: run, status: "failed", response_text: nil)
    create(:completion_kit_response, run: run, status: "pending", response_text: nil)
    run.update!(progress_total: 3)

    snap = run.progress_snapshot
    expect(snap[:generated_done]).to eq(2)
    expect(snap[:generated_total]).to eq(3)
    expect(snap[:generated_failed]).to eq(1)
    expect(snap[:judged_done]).to eq(0)
    expect(snap[:judged_total]).to eq(0)
  end
end
```

- [ ] **Step 2: Run — confirm they fail**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb`
Expected: failures.

- [ ] **Step 3: Implement the new methods on Run**

In `app/models/completion_kit/run.rb`, add (and remove the old `generate_responses!` / `judge_responses!` bodies — or repoint them; see Step 4):

```ruby
def start!
  rows = if dataset
           CsvProcessor.process_self(self)
         else
           [{}]
         end

  if rows.empty?
    return fail_with_summary!("Dataset has no rows")
  end

  client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))
  unless client.configured?
    return fail_with_summary!("LLM API not configured: #{client.configuration_errors.join(', ')}")
  end

  transaction do
    responses.destroy_all
    update!(
      status: "running",
      progress_current: 0,
      progress_total: rows.length,
      failure_summary: nil,
      error_message: nil
    )
    rows.each_with_index do |row, index|
      input = row.empty? ? nil : row.to_json
      response = responses.create!(
        status: "pending",
        row_index: index,
        input_data: input,
        expected_output: row.is_a?(Hash) ? row["expected_output"] : nil
      )
      GenerateRowJob.perform_later(id, response.id)
    end
  end

  broadcast_ui
  broadcast_clear_responses
  true
end

def outstanding_work_zero?
  return false if responses.where.not(status: Response::TERMINAL_STATUSES).exists?

  metric_ids = metrics.pluck(:id)
  return true if metric_ids.empty?

  succeeded_response_ids = responses.where(status: "succeeded").pluck(:id)
  expected_reviews = succeeded_response_ids.size * metric_ids.size

  return true if expected_reviews.zero?

  terminal_review_count = Review.where(
    response_id: succeeded_response_ids,
    metric_id: metric_ids,
    status: Review::TERMINAL_STATUSES
  ).count

  terminal_review_count >= expected_reviews
end

def mark_completed!
  update!(status: "completed")
  broadcast_ui
end

def progress_snapshot
  generated_done = responses.where(status: "succeeded").count
  generated_failed = responses.where(status: "failed").count
  generated_total = progress_total

  metric_count = metrics.count
  succeeded_count = generated_done
  judged_total = succeeded_count * metric_count
  judged_done = Review.joins(:response)
    .where(completion_kit_responses: { run_id: id }, status: "succeeded").count
  judged_failed = Review.joins(:response)
    .where(completion_kit_responses: { run_id: id }, status: "failed").count

  {
    generated_done: generated_done,
    generated_total: generated_total,
    generated_failed: generated_failed,
    judged_done: judged_done,
    judged_total: judged_total,
    judged_failed: judged_failed
  }
end

private

def fail_with_summary!(message)
  errors.add(:base, message)
  if persisted?
    update_columns(status: "failed", failure_summary: message, error_message: message)
    broadcast_ui
  end
  false
end
```

- [ ] **Step 4: Repoint or remove the old generate_responses! and judge_responses!**

Replace `Run#generate_responses!` with a deprecation stub that just calls `start!`:

```ruby
def generate_responses!
  start!
end
```

Remove `Run#judge_responses!` entirely (it is no longer reachable; the controller's `judge` action is also removed in Task 14).

- [ ] **Step 5: Run all run specs — confirm green**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb`

- [ ] **Step 6: Re-run the RunCompletionCheckJob spec from Task 12**

Run: `bundle exec rspec spec/jobs/completion_kit/run_completion_check_job_spec.rb`
Expected: green now that `outstanding_work_zero?` and `mark_completed!` exist.

- [ ] **Step 7: Commit**

```bash
git add app/models/completion_kit/run.rb spec/models/completion_kit/run_spec.rb
git commit -m "add Run#start, outstanding_work_zero?, mark_completed!, progress_snapshot"
```

---

### Task 14: Switch RunsController#generate to call run.start!

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb`
- Modify: `app/controllers/completion_kit/api/v1/runs_controller.rb`
- Test: `spec/requests/completion_kit/api/v1/runs_controller_spec.rb` if it exists, otherwise the controller spec under `spec/controllers/`

- [ ] **Step 1: Find the existing controller specs**

Run: `find spec -name "runs_controller_spec*"`

- [ ] **Step 2: Update the web controller**

In `app/controllers/completion_kit/runs_controller.rb`, replace the `generate` action:

```ruby
def generate
  if @run.start!
    redirect_to run_path(@run)
  else
    redirect_to run_path(@run), alert: @run.failure_summary || @run.errors.full_messages.to_sentence
  end
end
```

Remove the `judge` action and the route for it (Task 17 covers the route change). Judging is now triggered as part of `start!` via the per-row jobs.

- [ ] **Step 3: Update the API controller**

In `app/controllers/completion_kit/api/v1/runs_controller.rb`, replace the `generate` action:

```ruby
def generate
  if @run.start!
    render json: @run.reload, status: :accepted
  else
    render json: { errors: [@run.failure_summary || @run.errors.full_messages.to_sentence] }, status: :unprocessable_entity
  end
end
```

Remove the API `judge` action.

- [ ] **Step 4: Run any existing controller/request specs**

Run: `bundle exec rspec spec/controllers spec/requests 2>/dev/null || true`

Update assertions that expected the controller to call `GenerateJob.perform_later(@run.id)` to instead expect `run.start!` (or stub it). Remove tests for the deleted `judge` action.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit
git commit -m "controllers: replace generate/judge with run.start"
```

---

### Task 15: Delete or repoint old GenerateJob and JudgeJob

**Files:**
- Delete: `app/jobs/completion_kit/generate_job.rb`
- Delete: `app/jobs/completion_kit/judge_job.rb`
- Delete: `spec/jobs/completion_kit/generate_job_spec.rb`
- Delete: `spec/jobs/completion_kit/judge_job_spec.rb`

- [ ] **Step 1: Confirm nothing references them**

Run: `grep -rn "GenerateJob\|JudgeJob" app spec lib config 2>/dev/null | grep -v "Row\|Review\|spec/jobs/.*_job_spec"`

If anything is still referenced, fix the references first.

- [ ] **Step 2: Delete**

```bash
git rm app/jobs/completion_kit/generate_job.rb app/jobs/completion_kit/judge_job.rb spec/jobs/completion_kit/generate_job_spec.rb spec/jobs/completion_kit/judge_job_spec.rb
```

- [ ] **Step 3: Run the full suite to make sure nothing breaks**

Run: `bundle exec rspec`

- [ ] **Step 4: Commit**

```bash
git commit -m "remove old monolithic GenerateJob and JudgeJob"
```

---

### Task 16: Add Solid Queue concurrency limits to the new jobs

**Files:**
- Modify: `app/jobs/completion_kit/generate_row_job.rb`
- Modify: `app/jobs/completion_kit/judge_review_job.rb`
- Modify: `app/jobs/completion_kit/run_completion_check_job.rb`

(Solid Queue's `limits_concurrency` is a class-level DSL exposed by the `solid_queue` gem; it is a no-op in tests because Active Job's TestAdapter ignores it.)

- [ ] **Step 1: Add per-provider + per-run limits to GenerateRowJob**

In `app/jobs/completion_kit/generate_row_job.rb`, after `queue_as :llm`:

```ruby
limits_concurrency to: ENV.fetch("COMPLETION_KIT_LLM_CONCURRENCY", 10).to_i,
                   key: ->(run_id, _) { "llm:gen:#{Run.find_by(id: run_id)&.prompt&.llm_model_provider || 'unknown'}" },
                   duration: 10.minutes

limits_concurrency to: ENV.fetch("COMPLETION_KIT_PER_RUN_CONCURRENCY", 5).to_i,
                   key: ->(run_id, _) { "run:#{run_id}" },
                   duration: 10.minutes
```

- [ ] **Step 2: Add per-judge-provider + per-run limits to JudgeReviewJob**

In `app/jobs/completion_kit/judge_review_job.rb`, after `queue_as :llm`:

```ruby
limits_concurrency to: ENV.fetch("COMPLETION_KIT_LLM_CONCURRENCY", 10).to_i,
                   key: ->(response_id, _) {
                     run = Response.find_by(id: response_id)&.run
                     "llm:judge:#{run&.judge_model && ApiConfig.provider_for_model(run.judge_model) || 'unknown'}"
                   },
                   duration: 10.minutes

limits_concurrency to: ENV.fetch("COMPLETION_KIT_PER_RUN_CONCURRENCY", 5).to_i,
                   key: ->(response_id, _) { "run:#{Response.find_by(id: response_id)&.run_id}" },
                   duration: 10.minutes
```

- [ ] **Step 3: Serialize completion checks per run**

In `app/jobs/completion_kit/run_completion_check_job.rb`, after `queue_as :default`:

```ruby
limits_concurrency to: 1,
                   key: ->(run_id) { "run:#{run_id}:completion" },
                   duration: 5.minutes
```

- [ ] **Step 4: Run the full suite to confirm DSL doesn't blow up at load time**

Run: `bundle exec rspec spec/jobs`

(In specs the DSL is loaded but unused; the Active Job adapter is `:test`. If you see `NoMethodError: undefined method 'limits_concurrency'`, the engine spec dummy app is missing solid_queue — see Task 18.)

- [ ] **Step 5: Commit**

```bash
git add app/jobs/completion_kit
git commit -m "add concurrency limits to row and review jobs"
```

---

### Task 17: Remove the judge route, keep generate

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/completion_kit/runs/_actions.html.erb` if it has a "Judge" button

- [ ] **Step 1: Remove the judge route in both web and API**

In `config/routes.rb`, remove `post :judge` from both the engine routes and `api/v1/runs`.

- [ ] **Step 2: Remove any "Judge" link in views**

Run: `grep -rn "judge_run_path\|:judge" app/views` and remove the calls, since judging now happens automatically as part of generate.

- [ ] **Step 3: Run full spec — should be green**

Run: `bundle exec rspec`

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb app/views
git commit -m "drop standalone judge action; judging now triggered per-row"
```

---

### Task 18: Make the engine's spec environment Solid-Queue-aware

**Files:**
- Modify: `Gemfile` (engine root) — add solid_queue as a development dependency for the dummy app
- Modify: `completion_kit.gemspec`

- [ ] **Step 1: Add solid_queue to the engine's dev dependencies**

In `completion_kit.gemspec`, add:

```ruby
spec.add_development_dependency "solid_queue", "~> 1.0"
```

- [ ] **Step 2: Bundle**

Run: `bundle install`

- [ ] **Step 3: Confirm Gemfile.lock has solid_queue**

Run: `grep solid_queue Gemfile.lock`

- [ ] **Step 4: Re-run the full spec**

Run: `bundle exec rspec`
Expected: green. The `limits_concurrency` DSL now resolves at load time even though the test adapter ignores it.

- [ ] **Step 5: Commit**

```bash
git add completion_kit.gemspec Gemfile.lock
git commit -m "add solid_queue as engine dev dependency for spec load"
```

---

### Task 19: Switch the standalone production and development queue adapters

**Files:**
- Modify: `standalone/config/environments/production.rb`
- Modify: `standalone/config/environments/development.rb`
- Modify: `standalone/Procfile.dev` (create if missing)

- [ ] **Step 1: Switch production**

In `standalone/config/environments/production.rb`:

Replace `config.active_job.queue_adapter = :async` with `config.active_job.queue_adapter = :solid_queue`.

- [ ] **Step 2: Switch development**

In `standalone/config/environments/development.rb`:

Replace `config.active_job.queue_adapter = :async` with `config.active_job.queue_adapter = :solid_queue`.

- [ ] **Step 3: Update the dev Procfile**

If `standalone/Procfile.dev` does not exist, check `standalone/bin/dev` for the existing process list. Either way, ensure there is a `worker` line:

```
web: bin/rails s
worker: bin/jobs
```

- [ ] **Step 4: Boot locally and verify**

Run: `cd standalone && foreman start -f Procfile.dev` (or `bin/dev` if that's the pattern).

Trigger a test run from the UI and confirm in `standalone/log/development.log` that `GenerateRowJob` is enqueued and processed by the worker.

- [ ] **Step 5: Commit**

```bash
git add standalone/config/environments standalone/Procfile.dev
git commit -m "switch standalone queue adapter to solid_queue"
```

---

### Task 20: Add the cutover rake task and boot warning

**Files:**
- Create: `lib/tasks/completion_kit_runs.rake`
- Create: `config/initializers/completion_kit_concurrency_check.rb` (in standalone)

- [ ] **Step 1: Add the rake task**

Create `lib/tasks/completion_kit_runs.rake`:

```ruby
namespace :completion_kit do
  desc "Mark in-flight runs as failed (for use after the queue adapter cutover)"
  task mark_interrupted_runs_failed: :environment do
    scope = CompletionKit::Run.where(status: "running")
    count = scope.count
    scope.update_all(
      status: "failed",
      failure_summary: "Interrupted by deploy",
      updated_at: Time.current
    )
    puts "Marked #{count} runs as failed."
  end
end
```

- [ ] **Step 2: Add the boot-time warning**

Create `standalone/config/initializers/completion_kit_concurrency_check.rb`:

```ruby
Rails.application.config.after_initialize do
  threads = ENV.fetch("SOLID_QUEUE_THREADS", 10).to_i
  llm_cap = ENV.fetch("COMPLETION_KIT_LLM_CONCURRENCY", 10).to_i

  if threads < llm_cap
    Rails.logger.warn(
      "[CompletionKit] SOLID_QUEUE_THREADS=#{threads} is less than " \
      "COMPLETION_KIT_LLM_CONCURRENCY=#{llm_cap}; threads will be the " \
      "actual bottleneck and the per-provider cap will never be reached."
    )
  end
end
```

- [ ] **Step 3: Verify the task is loadable**

Run: `cd standalone && bin/rails completion_kit:mark_interrupted_runs_failed`
Expected: prints "Marked 0 runs as failed."

- [ ] **Step 4: Commit**

```bash
git add lib/tasks/completion_kit_runs.rake standalone/config/initializers/completion_kit_concurrency_check.rb
git commit -m "add cutover rake task and concurrency boot warning"
```

> **PR 2 ends here.** Before merging:
> 1. Confirm Render Worker service has been created with the start command `cd standalone && bin/jobs` and the env vars from the spec (§Deployment in the design doc).
> 2. Add a one-time post-deploy hook (or run manually after deploy) for `cd standalone && bin/rails completion_kit:mark_interrupted_runs_failed` to clean up any runs that were in flight under `:async` at cutover.
> 3. After deploy, kick off a small generation run from the UI; confirm progress is visible and a worker process is doing the work (Render → Worker service logs).

---

# Phase 3 (PR 3): UI + API

> Goal of this PR: rewrite the status header and response row to reflect the new four-counter progress model, add a Retry-Failed-Rows action, extend the JSON API.

---

### Task 21: Rewrite the status header partial to use progress_snapshot

**Files:**
- Modify: `app/views/completion_kit/runs/_status_header.html.erb`
- Test: existing run-page request spec (or create one)

- [ ] **Step 1: Replace the partial**

Open `app/views/completion_kit/runs/_status_header.html.erb` and replace its contents with:

```erb
<% snap = run.progress_snapshot %>
<div id="run_status_header" class="run-status-header">
  <% if run.status == "pending" %>
    <span class="status-badge status-pending">Pending</span>
  <% elsif run.status == "running" %>
    <span class="status-badge status-running">● Running</span>
  <% elsif run.status == "completed" %>
    <span class="status-badge status-completed">✓ Completed</span>
    <% if run.avg_score %>
      <span class="run-avg-score">avg score <%= run.avg_score %></span>
    <% end %>
  <% elsif run.status == "failed" %>
    <span class="status-badge status-failed">✕ Failed</span>
    <% if run.failure_summary.present? %>
      <span class="failure-summary"><%= run.failure_summary %></span>
    <% end %>
  <% end %>

  <% if run.status.in?(%w[running completed]) %>
    <div class="run-progress-block">
      <div class="run-progress-line">
        Generated <%= snap[:generated_done] %>/<%= snap[:generated_total] %>
        <% if snap[:generated_failed] > 0 %>
          <span class="failure-count">(<%= snap[:generated_failed] %> failed)</span>
        <% end %>
      </div>
      <% if snap[:judged_total] > 0 %>
        <div class="run-progress-line">
          Judged <%= snap[:judged_done] %>/<%= snap[:judged_total] %>
          <% if snap[:judged_failed] > 0 %>
            <span class="failure-count">(<%= snap[:judged_failed] %> failed)</span>
          <% end %>
        </div>
      <% end %>
    </div>

    <% failed_count = snap[:generated_failed] + snap[:judged_failed] %>
    <% if failed_count > 0 %>
      <%= button_to "Retry #{failed_count} failed rows", retry_failures_run_path(run),
            method: :post, class: "btn btn-secondary btn-sm retry-failures-btn" %>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 2: Confirm the run show page still renders without error**

Run: `bundle exec rspec spec/requests` if there are request specs; otherwise smoke-test in the dev server.

- [ ] **Step 3: Commit**

```bash
git add app/views/completion_kit/runs/_status_header.html.erb
git commit -m "rewrite status header for split gen/judge counters"
```

---

### Task 22: Rewrite the response row partial

**Files:**
- Modify: `app/views/completion_kit/runs/_response_row.html.erb`

- [ ] **Step 1: Read the current partial**

Run: `cat app/views/completion_kit/runs/_response_row.html.erb`

- [ ] **Step 2: Replace it**

Open the file and replace the contents with a structure that branches on `response.status`:

```erb
<div id="response_<%= response.id %>" class="response-row response-status-<%= response.status %>">
  <div class="response-header">
    <span class="response-index">#<%= (response.row_index || 0) + 1 %></span>
    <% case response.status
       when "pending" %>
      <span class="response-state state-pending">queued</span>
    <% when "retrying" %>
      <span class="response-state state-retrying">retrying… attempt <%= response.attempts %>/5</span>
    <% when "succeeded" %>
      <span class="response-state state-succeeded">✓</span>
    <% when "failed" %>
      <% err = response.error_payload %>
      <span class="response-state state-failed" title="<%= err && err[:message] %>">
        Failed: <%= err && err[:provider]&.titleize %>
        <%= err && err[:status] %>
        — <%= err && err[:message]&.truncate(80) %>
      </span>
      <%= button_to "Retry", retry_failures_run_path(run, only: response.id),
            method: :post, class: "btn btn-link btn-xs retry-row-btn" %>
    <% end %>
  </div>

  <% if response.status == "succeeded" %>
    <div class="response-text"><%= simple_format(response.response_text) %></div>
    <% if response.expected_output.present? %>
      <div class="expected-output">Expected: <%= response.expected_output %></div>
    <% end %>
    <div class="reviews">
      <% response.reviews.each do |review| %>
        <div id="review_<%= review.id %>" class="review review-status-<%= review.status %>">
          <span class="review-metric"><%= review.metric_name %></span>
          <% case review.status
             when "succeeded" %>
            <span class="review-score"><%= review.ai_score %></span>
            <% if review.ai_feedback.present? %>
              <details><summary>feedback</summary><%= simple_format(review.ai_feedback) %></details>
            <% end %>
          <% when "retrying" %>
            <span class="review-state">retrying… <%= review.attempts %>/5</span>
          <% when "failed" %>
            <% rerr = review.error_payload %>
            <span class="review-state state-failed" title="<%= rerr && rerr[:message] %>">
              Failed: <%= rerr && rerr[:provider]&.titleize %>
              <%= rerr && rerr[:status] %>
            </span>
          <% else %>
            <span class="review-state">queued</span>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 3: Smoke-test in the dev server**

Boot the dev stack and trigger a test run with a flaky stub (or a real provider with an intentionally bad key) to confirm the failed/retrying/succeeded states render.

- [ ] **Step 4: Commit**

```bash
git add app/views/completion_kit/runs/_response_row.html.erb
git commit -m "rewrite response row partial for new states and provider error"
```

---

### Task 23: Add retry_failures controller action and route

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/completion_kit/runs_controller.rb`
- Modify: `app/controllers/completion_kit/api/v1/runs_controller.rb`
- Test: `spec/requests/completion_kit/runs_retry_failures_spec.rb` (create)

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, inside the engine `resources :runs do member do … end` block, add `post :retry_failures`. Inside the `api/v1` `resources :runs do member do … end`, add the same.

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/completion_kit/runs_retry_failures_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "POST /completion_kit/runs/:id/retry_failures", type: :request do
  let(:run) { create(:completion_kit_run, status: "completed") }

  before do
    allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_ui)
    allow(CompletionKit::GenerateRowJob).to receive(:perform_later)
  end

  it "resets failed responses to pending and re-enqueues their jobs" do
    failed = create(:completion_kit_response, :failed, run: run, row_index: 0)
    succeeded = create(:completion_kit_response, run: run, status: "succeeded", row_index: 1, response_text: "ok")

    post "/completion_kit/runs/#{run.id}/retry_failures"

    failed.reload
    succeeded.reload

    expect(failed.status).to eq("pending")
    expect(failed.error_class).to be_nil
    expect(failed.attempts).to eq(0)
    expect(succeeded.status).to eq("succeeded")
    expect(run.reload.status).to eq("running")
    expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed.id)
    expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later).with(run.id, succeeded.id)
  end

  it "scopes to a single response when only param is supplied" do
    failed_a = create(:completion_kit_response, :failed, run: run, row_index: 0)
    failed_b = create(:completion_kit_response, :failed, run: run, row_index: 1)

    post "/completion_kit/runs/#{run.id}/retry_failures", params: { only: failed_a.id }

    expect(failed_a.reload.status).to eq("pending")
    expect(failed_b.reload.status).to eq("failed")
    expect(CompletionKit::GenerateRowJob).to have_received(:perform_later).with(run.id, failed_a.id)
    expect(CompletionKit::GenerateRowJob).not_to have_received(:perform_later).with(run.id, failed_b.id)
  end
end
```

- [ ] **Step 3: Run — confirm failure**

Run: `bundle exec rspec spec/requests/completion_kit/runs_retry_failures_spec.rb`
Expected: routing error.

- [ ] **Step 4: Implement the action**

In `app/controllers/completion_kit/runs_controller.rb`, add to `before_action :set_run` and define:

```ruby
def retry_failures
  scope = @run.responses.where(status: "failed")
  scope = scope.where(id: params[:only]) if params[:only].present?

  ActiveRecord::Base.transaction do
    failed_response_ids = scope.pluck(:id)
    Review.where(response_id: failed_response_ids, status: "failed").update_all(
      status: "pending",
      attempts: 0,
      error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
      ai_score: nil, ai_feedback: nil
    )
    scope.update_all(
      status: "pending",
      attempts: 0,
      error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
      response_text: nil
    )
    @run.update!(status: "running")
    failed_response_ids.each { |rid| GenerateRowJob.perform_later(@run.id, rid) }
  end

  @run.send(:broadcast_ui)
  redirect_to run_path(@run)
end
```

Add `:retry_failures` to the `before_action :set_run` only-list.

- [ ] **Step 5: Implement the API equivalent**

In `app/controllers/completion_kit/api/v1/runs_controller.rb`:

```ruby
def retry_failures
  scope = @run.responses.where(status: "failed")
  scope = scope.where(id: params[:only]) if params[:only].present?

  ActiveRecord::Base.transaction do
    failed_response_ids = scope.pluck(:id)
    CompletionKit::Review.where(response_id: failed_response_ids, status: "failed").update_all(
      status: "pending", attempts: 0,
      error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
      ai_score: nil, ai_feedback: nil
    )
    scope.update_all(
      status: "pending", attempts: 0,
      error_provider: nil, error_class: nil, error_status: nil, error_message: nil,
      response_text: nil
    )
    @run.update!(status: "running")
    failed_response_ids.each { |rid| CompletionKit::GenerateRowJob.perform_later(@run.id, rid) }
  end

  render json: @run.reload, status: :accepted
end
```

Add `:retry_failures` to the `before_action :set_run` only-list.

- [ ] **Step 6: Run — confirm green**

Run: `bundle exec rspec spec/requests/completion_kit/runs_retry_failures_spec.rb`

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/completion_kit spec/requests/completion_kit
git commit -m "add retry_failures action for both web and API"
```

---

### Task 24: Extend Run#as_json with the new progress object

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Modify: `spec/models/completion_kit/json_serialization_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/models/completion_kit/json_serialization_spec.rb`:

```ruby
describe "Run#as_json includes progress object and failed_response_ids" do
  let(:run) { create(:completion_kit_run, progress_total: 2) }

  it "includes a progress hash with generated and judged sub-objects" do
    create(:completion_kit_response, run: run, status: "succeeded", response_text: "a")
    create(:completion_kit_response, :failed, run: run)

    payload = run.as_json
    expect(payload[:progress][:generated]).to include(done: 1, total: 2, failed: 1)
    expect(payload[:progress][:judged]).to include(done: 0, total: 0, failed: 0)
    expect(payload[:failed_response_ids]).to be_an(Array)
    expect(payload[:failed_response_ids].size).to eq(1)
  end

  it "preserves legacy progress_current and progress_total fields" do
    payload = run.as_json
    expect(payload).to have_key(:progress_current)
    expect(payload).to have_key(:progress_total)
  end
end
```

- [ ] **Step 2: Run — confirm failure**

Run: `bundle exec rspec spec/models/completion_kit/json_serialization_spec.rb`

- [ ] **Step 3: Update `Run#as_json`**

In `app/models/completion_kit/run.rb`, replace `as_json` with:

```ruby
def as_json(options = {})
  snap = progress_snapshot
  {
    id: id, name: name, status: status, prompt_id: prompt_id,
    dataset_id: dataset_id, judge_model: judge_model, temperature: temperature,
    created_at: created_at, updated_at: updated_at,
    responses_count: responses.count, avg_score: avg_score,
    progress_current: snap[:generated_done],
    progress_total: snap[:generated_total],
    progress: {
      generated: { done: snap[:generated_done], total: snap[:generated_total], failed: snap[:generated_failed] },
      judged:    { done: snap[:judged_done],    total: snap[:judged_total],    failed: snap[:judged_failed] }
    },
    failed_response_ids: responses.where(status: "failed").pluck(:id),
    failure_summary: failure_summary,
    error_message: error_message,
    metric_ids: metric_ids
  }
end
```

- [ ] **Step 4: Run — confirm green**

Run: `bundle exec rspec spec/models/completion_kit/json_serialization_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/run.rb spec/models/completion_kit/json_serialization_spec.rb
git commit -m "extend Run#as_json with progress object and failed_response_ids"
```

---

### Task 25: (Optional) mount mission_control-jobs dashboard

**Files:**
- Modify: `standalone/config/routes.rb`

- [ ] **Step 1: Mount behind the existing auth**

In `standalone/config/routes.rb`, add inside the existing auth-protected route block:

```ruby
authenticate :admin do
  mount MissionControl::Jobs::Engine, at: "/jobs"
end
```

(Replace `:admin` constraint with whatever auth pattern the app already uses — check existing routes to match.)

- [ ] **Step 2: Smoke test locally**

Boot the dev stack, hit `/jobs` in the browser, confirm the dashboard renders behind auth.

- [ ] **Step 3: Commit**

```bash
git add standalone/config/routes.rb
git commit -m "mount mission_control-jobs at /jobs"
```

> **PR 3 ends here.** Open the PR with the task commits. After merge, smoke-test in production: trigger a multi-row run, confirm progress counters increment and any failed rows surface a provider-named badge with a working Retry button.

---

# Self-review

After writing all three phases, this section was used to verify spec coverage. Resolved gaps:

- Spec §Provider error visibility → Tasks 9, 10, 11, 22 cover error capture and rendering.
- Spec §Concurrency → Tasks 6, 16, 20 (config, DSL, boot warning).
- Spec §Retry policy → Tasks 10, 11.
- Spec §In-flight retry visibility → `before_perform` callbacks in Tasks 10 and 11.
- Spec §Progress UI → Tasks 13 (`progress_snapshot`), 21 (status header).
- Spec §Race-free completion check → Tasks 12, 16 (concurrency cap).
- Spec §Retry-failed-rows action → Task 23.
- Spec §JSON API → Task 24 (`Run#as_json`); Task 23 (route).
- Spec §Deployment → Tasks 5, 6, 18, 19, 20 + the PR 2 footnote describing the manual Render Worker creation.
- Spec §Observability → Task 25.
- Spec §In-flight runs at the cutover → Task 20 + PR 2 footnote.
- Spec §Schema changes → Tasks 1, 2, 3, 4.

No placeholders, no "TBD", no "similar to task N" without code, no references to undefined methods. Method signatures are consistent across tasks (`outstanding_work_zero?`, `mark_completed!`, `progress_snapshot`, `start!`, `failure_summary`, `error_payload`, etc.).
