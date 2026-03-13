# Authentication & Feature Audit Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add password protection to the CompletionKit engine and verify/fix all features end-to-end.

**Architecture:** Authentication is a `before_action` on the engine's ApplicationController with two modes (HTTP basic auth or custom hook). Feature audit adds integration tests with Faraday-level HTTP stubs to verify the full generation and judging pipeline. A bug fix removes the `input_data` presence validation on Response to support no-dataset runs.

**Tech Stack:** Rails 7, RSpec, FactoryBot, Faraday stubs

**Spec:** `docs/superpowers/specs/2026-03-13-auth-and-feature-audit-design.md`

---

## Chunk 1: Authentication

### Task 1: Add auth config attributes to Configuration

**Files:**
- Modify: `lib/completion_kit.rb:8-22`
- Test: `spec/lib/completion_kit_auth_config_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/lib/completion_kit_auth_config_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "CompletionKit auth configuration" do
  after { CompletionKit.instance_variable_set(:@config, nil) }

  it "exposes username, password, and auth_strategy" do
    CompletionKit.configure do |c|
      c.username = "admin"
      c.password = "secret"
    end

    expect(CompletionKit.config.username).to eq("admin")
    expect(CompletionKit.config.password).to eq("secret")
    expect(CompletionKit.config.auth_strategy).to be_nil
  end

  it "exposes auth_strategy" do
    strategy = ->(controller) { controller.head(:unauthorized) }

    CompletionKit.configure do |c|
      c.auth_strategy = strategy
    end

    expect(CompletionKit.config.auth_strategy).to eq(strategy)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit_auth_config_spec.rb`
Expected: FAIL with NoMethodError for `username=`

- [ ] **Step 3: Implement config attributes**

In `lib/completion_kit.rb`, add to the `Configuration` class:

```ruby
attr_accessor :username, :password, :auth_strategy
```

These go on line 10 alongside the existing `attr_accessor` lines. No defaults needed — they default to `nil`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/completion_kit_auth_config_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/completion_kit.rb spec/lib/completion_kit_auth_config_spec.rb
git commit -m "feat: add username, password, auth_strategy config attributes"
```

---

### Task 2: Add ConfigurationError and authenticate_completion_kit! to ApplicationController

**Files:**
- Modify: `lib/completion_kit.rb` — add ConfigurationError class
- Modify: `app/controllers/completion_kit/application_controller.rb`
- Test: `spec/requests/completion_kit/auth_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/requests/completion_kit/auth_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "CompletionKit authentication", type: :request do
  let(:base_path) { "/completion_kit/prompts" }

  after { CompletionKit.instance_variable_set(:@config, nil) }

  context "with basic auth configured" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
        c.password = "secret"
      end
    end

    it "allows access with correct credentials" do
      create(:completion_kit_prompt)

      get base_path, headers: {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
      }

      expect(response).to have_http_status(:ok)
    end

    it "rejects access with wrong credentials" do
      get base_path, headers: {
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "wrong")
      }

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects access with no credentials" do
      get base_path

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with custom auth_strategy" do
    before do
      CompletionKit.configure do |c|
        c.auth_strategy = ->(controller) {
          controller.head(:unauthorized) unless controller.request.headers["X-Custom-Auth"] == "valid"
        }
      end
    end

    it "allows access when strategy passes" do
      create(:completion_kit_prompt)

      get base_path, headers: { "X-Custom-Auth" => "valid" }

      expect(response).to have_http_status(:ok)
    end

    it "rejects access when strategy fails" do
      get base_path, headers: { "X-Custom-Auth" => "invalid" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with both basic auth and auth_strategy configured" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
        c.password = "secret"
        c.auth_strategy = ->(controller) { true }
      end
    end

    it "raises ConfigurationError" do
      expect { get base_path }.to raise_error(
        CompletionKit::ConfigurationError,
        /Cannot configure both/
      )
    end
  end

  context "with only username set (no password)" do
    before do
      CompletionKit.configure do |c|
        c.username = "admin"
      end
    end

    it "raises ConfigurationError" do
      expect { get base_path }.to raise_error(
        CompletionKit::ConfigurationError,
        /Both username and password are required/
      )
    end
  end

  context "with no auth in non-production" do
    it "allows open access" do
      create(:completion_kit_prompt)

      get base_path

      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/auth_spec.rb`
Expected: FAIL — no auth enforcement, ConfigurationError not defined

- [ ] **Step 3: Add ConfigurationError**

In `lib/completion_kit.rb`, add inside `module CompletionKit` (before the `Configuration` class):

```ruby
class ConfigurationError < StandardError; end
```

- [ ] **Step 4: Implement authenticate_completion_kit!**

Replace `app/controllers/completion_kit/application_controller.rb` with:

```ruby
module CompletionKit
  class ApplicationController < ActionController::Base
    layout "completion_kit/application"

    before_action :authenticate_completion_kit!

    private

    def authenticate_completion_kit!
      cfg = CompletionKit.config

      if cfg.auth_strategy && (cfg.username || cfg.password)
        raise CompletionKit::ConfigurationError,
          "Cannot configure both username/password and auth_strategy. Use one or the other."
      end

      if (cfg.username && !cfg.password) || (cfg.password && !cfg.username)
        raise CompletionKit::ConfigurationError,
          "Both username and password are required for built-in auth."
      end

      if cfg.auth_strategy
        cfg.auth_strategy.call(self)
      elsif cfg.username && cfg.password
        authenticate_or_request_with_http_basic("CompletionKit") do |u, p|
          ActiveSupport::SecurityUtils.secure_compare(u, cfg.username) &
            ActiveSupport::SecurityUtils.secure_compare(p, cfg.password)
        end
      elsif Rails.env.production?
        render plain: "CompletionKit authentication not configured. See README for setup instructions.",
               status: :forbidden
      end
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/auth_spec.rb`
Expected: PASS

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `bundle exec rspec`
Expected: All tests pass (existing tests run without auth since test env has no auth configured)

- [ ] **Step 7: Commit**

```bash
git add lib/completion_kit.rb app/controllers/completion_kit/application_controller.rb spec/requests/completion_kit/auth_spec.rb
git commit -m "feat: add password protection with basic auth and custom auth hook"
```

---

### Task 3: Add production hard-block test

**Files:**
- Modify: `spec/requests/completion_kit/auth_spec.rb`

- [ ] **Step 1: Add production block test**

Append to `spec/requests/completion_kit/auth_spec.rb` inside the main describe block:

```ruby
context "with no auth in production" do
  around do |example|
    original_env = Rails.env
    Rails.env = ActiveSupport::EnvironmentInquirer.new("production")
    example.run
  ensure
    Rails.env = original_env
  end

  it "blocks access with 403" do
    get base_path

    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("authentication not configured")
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/auth_spec.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add spec/requests/completion_kit/auth_spec.rb
git commit -m "test: add production hard-block auth test"
```

---

### Task 4: Add boot-time warning for no auth in development

**Files:**
- Modify: `lib/completion_kit/engine.rb`

- [ ] **Step 1: Add after_initialize warning**

In `lib/completion_kit/engine.rb`, add inside the `Engine` class after the existing initializers:

```ruby
config.after_initialize do
  cfg = CompletionKit.config
  unless cfg.username || cfg.auth_strategy
    Rails.logger.warn "[CompletionKit] WARNING: No authentication configured. All routes are publicly accessible."
  end
end
```

- [ ] **Step 2: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add lib/completion_kit/engine.rb
git commit -m "feat: log warning when no auth is configured"
```

---

### Task 5: Update README with auth documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add authentication section**

After the "Setup" section (after line 39 in `README.md`), add:

```markdown
## Authentication

CompletionKit requires authentication in production. In development, routes are open by default (with a log warning).

### Basic Auth (recommended for simple setups)

```ruby
# config/initializers/completion_kit.rb
CompletionKit.configure do |c|
  c.username = "admin"
  c.password = ENV["COMPLETION_KIT_PASSWORD"]
end
```

### Custom Auth (Devise, etc.)

```ruby
# config/initializers/completion_kit.rb
CompletionKit.configure do |c|
  c.auth_strategy = ->(controller) { controller.authenticate_user! }
end
```

Only one mode can be active — setting both raises a `ConfigurationError`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add authentication setup instructions to README"
```

---

## Chunk 2: Feature Audit — Bug Fix & Prompt Versioning

### Task 6: Fix input_data presence validation on Response

**Files:**
- Modify: `app/models/completion_kit/response.rb:8`
- Modify: `spec/factories/responses.rb`
- Test: `spec/models/completion_kit/response_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/completion_kit/response_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::Response, type: :model do
  it "allows nil input_data for no-dataset runs" do
    response = build(:completion_kit_response, input_data: nil)
    expect(response).to be_valid
  end

  it "requires response_text" do
    response = build(:completion_kit_response, response_text: nil)
    expect(response).not_to be_valid
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/response_spec.rb`
Expected: FAIL on "allows nil input_data"

- [ ] **Step 3: Remove input_data presence validation**

In `app/models/completion_kit/response.rb`, delete line 8:

```ruby
validates :input_data, presence: true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/completion_kit/response_spec.rb`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add app/models/completion_kit/response.rb spec/models/completion_kit/response_spec.rb
git commit -m "fix: allow nil input_data on Response for no-dataset runs"
```

---

### Task 7: Add "Make current" button to prompt show page

**Files:**
- Modify: `app/views/completion_kit/prompts/show.html.erb`
- Test: `spec/requests/completion_kit/prompts_spec.rb`

- [ ] **Step 1: Write the failing test**

Add to `spec/requests/completion_kit/prompts_spec.rb`:

```ruby
it "shows Make current button for non-current versions and Current badge for current" do
  v1 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 1, current: true)
  v2 = create(:completion_kit_prompt, name: "Prompt", family_key: "fam-1", version_number: 2, current: false)

  get "/completion_kit/prompts/#{v1.id}"

  expect(response.body).to include("Current")
  expect(response.body).to include("Make current")
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb`
Expected: FAIL — "Make current" not found in response body

- [ ] **Step 3: Add versions section to prompt show page**

In `app/views/completion_kit/prompts/show.html.erb`, add after the closing `</section>` of the Template section (after line 27):

```erb
<% versions = @prompt.family_versions %>
<% if versions.size > 1 %>
  <section class="ck-card--spaced">
    <p class="ck-kicker">Versions</p>
    <table class="ck-results-table" style="margin-top: 0.5rem;">
      <thead>
        <tr>
          <th>Version</th>
          <th>Model</th>
          <th>Created</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <% versions.each do |v| %>
          <tr>
            <td><strong>v<%= v.version_number %></strong></td>
            <td><span class="ck-chip ck-chip--soft"><%= v.llm_model %></span></td>
            <td class="ck-meta-copy"><%= time_ago_in_words(v.created_at) %> ago</td>
            <td>
              <% if v.current? %>
                <span class="ck-chip">Current</span>
              <% else %>
                <%= button_to "Make current", publish_prompt_path(v), method: :post, class: ck_button_classes(:light, variant: :outline), form_class: "inline-block" %>
              <% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
<% end %>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `bundle exec rspec`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add app/views/completion_kit/prompts/show.html.erb spec/requests/completion_kit/prompts_spec.rb
git commit -m "feat: add Make current button for prompt version switching"
```

---

### Task 8: Verify prompt versioning and public API

**Files:**
- Test: `spec/models/completion_kit/prompt_versioning_spec.rb`

- [ ] **Step 1: Write the tests**

Create `spec/models/completion_kit/prompt_versioning_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Prompt versioning and public API", type: :model do
  let!(:v1) do
    create(:completion_kit_prompt,
      name: "Summarizer", family_key: "sum-1", version_number: 1,
      template: "Summarize {{content}}", current: true)
  end
  let!(:v2) do
    create(:completion_kit_prompt,
      name: "Summarizer", family_key: "sum-1", version_number: 2,
      template: "Briefly summarize {{content}}", current: false, published_at: nil)
  end

  describe "Prompt#publish!" do
    it "makes the target version current and unpublishes others" do
      v2.publish!

      expect(v2.reload.current).to be true
      expect(v2.published_at).to be_present
      expect(v1.reload.current).to be false
    end

    it "supports rollback by publishing an older version" do
      v2.publish!
      v1.publish!

      expect(v1.reload.current).to be true
      expect(v2.reload.current).to be false
    end
  end

  describe "Prompt#clone_as_new_version" do
    it "creates a new version with incremented number" do
      v3 = v1.clone_as_new_version

      expect(v3.version_number).to eq(3)
      expect(v3.current).to be false
      expect(v3.family_key).to eq("sum-1")
      expect(v3.template).to eq(v1.template)
    end
  end

  describe "CompletionKit.current_prompt" do
    it "returns the current version by name" do
      result = CompletionKit.current_prompt("Summarizer")
      expect(result.id).to eq(v1.id)
    end

    it "returns the current version by family_key" do
      result = CompletionKit.current_prompt("sum-1")
      expect(result.id).to eq(v1.id)
    end

    it "returns updated current after publish" do
      v2.publish!
      result = CompletionKit.current_prompt("Summarizer")
      expect(result.id).to eq(v2.id)
    end
  end

  describe "CompletionKit.current_prompt_payload" do
    it "returns structured payload" do
      payload = CompletionKit.current_prompt_payload("Summarizer")

      expect(payload[:name]).to eq("Summarizer")
      expect(payload[:family_key]).to eq("sum-1")
      expect(payload[:version_number]).to eq(1)
      expect(payload[:template]).to eq("Summarize {{content}}")
      expect(payload[:generation_model]).to eq("gpt-4.1")
    end
  end

  describe "CompletionKit.render_current_prompt" do
    it "substitutes variables into the current template" do
      result = CompletionKit.render_current_prompt("Summarizer", { "content" => "the news" })
      expect(result).to eq("Summarize the news")
    end
  end
end
```

- [ ] **Step 2: Run tests**

Run: `bundle exec rspec spec/models/completion_kit/prompt_versioning_spec.rb`
Expected: All PASS (this verifies existing behavior)

- [ ] **Step 3: Commit**

```bash
git add spec/models/completion_kit/prompt_versioning_spec.rb
git commit -m "test: verify prompt versioning, rollback, and public API"
```

---

## Chunk 3: Feature Audit — End-to-End Pipeline

### Task 9: End-to-end generation pipeline test

**Files:**
- Test: `spec/integration/completion_kit/generation_pipeline_spec.rb`

- [ ] **Step 1: Write the integration test**

Create `spec/integration/completion_kit/generation_pipeline_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "End-to-end generation pipeline", type: :model do
  let(:prompt) do
    create(:completion_kit_prompt,
      name: "Summarizer", template: "Summarize {{content}} for {{audience}}",
      llm_model: "gpt-4.1")
  end

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")
  end

  context "with a dataset" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    let(:dataset) do
      create(:completion_kit_dataset, csv_data: <<~CSV)
        content,audience,expected_output
        "Release notes","developers","A developer-focused summary"
        "Company update","executives","An executive briefing"
      CSV
    end

    before do
      stubs.post("/v1/chat/completions") do |env|
        body = JSON.parse(env.body)
        user_msg = body["messages"].find { |m| m["role"] == "user" }["content"]

        reply = if user_msg.include?("Release notes")
                  "Here is a developer summary of the release notes."
                else
                  "Here is an executive briefing of the company update."
                end

        [200, { "Content-Type" => "application/json" }, {
          choices: [{ message: { content: reply } }]
        }.to_json]
      end

      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
        original.call(*args, **kwargs) do |builder|
          builder.adapter :test, stubs
        end
      end
    end

    it "generates responses with correct input_data, response_text, and status transitions" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: dataset, name: "Pipeline test")

      expect(run.status).to eq("pending")
      run.generate_responses!

      expect(run.reload.status).to eq("completed")
      expect(run.responses.count).to eq(2)

      r1 = run.responses.order(:id).first
      expect(JSON.parse(r1.input_data)["content"]).to eq("Release notes")
      expect(r1.response_text).to include("developer summary")
      expect(r1.expected_output).to eq("A developer-focused summary")

      r2 = run.responses.order(:id).last
      expect(JSON.parse(r2.input_data)["content"]).to eq("Company update")
      expect(r2.response_text).to include("executive briefing")
    end
  end

  context "without a dataset" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      stubs.post("/v1/chat/completions") do
        [200, { "Content-Type" => "application/json" }, {
          choices: [{ message: { content: "Raw prompt response" } }]
        }.to_json]
      end

      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
        original.call(*args, **kwargs) do |builder|
          builder.adapter :test, stubs
        end
      end
    end

    it "generates a single response with nil input_data" do
      run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No dataset test")

      run.generate_responses!

      expect(run.reload.status).to eq("completed")
      expect(run.responses.count).to eq(1)
      expect(run.responses.first.input_data).to be_nil
      expect(run.responses.first.response_text).to eq("Raw prompt response")
    end
  end
end
```

- [ ] **Step 2: Run test**

Run: `bundle exec rspec spec/integration/completion_kit/generation_pipeline_spec.rb`
Expected: PASS (if input_data validation is already fixed in Task 6)

- [ ] **Step 3: Commit**

```bash
git add spec/integration/completion_kit/generation_pipeline_spec.rb
git commit -m "test: end-to-end generation pipeline with Faraday stubs"
```

---

### Task 10: End-to-end judging pipeline test

**Files:**
- Test: `spec/integration/completion_kit/judging_pipeline_spec.rb`

- [ ] **Step 1: Write the integration test**

Create `spec/integration/completion_kit/judging_pipeline_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "End-to-end judging pipeline", type: :model do
  let(:metric) do
    create(:completion_kit_metric, name: "Relevance", criteria: "Is the output relevant?")
  end
  let(:criteria) do
    c = create(:completion_kit_criteria, name: "QA Criteria")
    CompletionKit::CriteriaMembership.create!(criteria: c, metric: metric, position: 1)
    c
  end
  let(:prompt) do
    create(:completion_kit_prompt, template: "Summarize {{content}}", llm_model: "gpt-4.1")
  end
  let(:run) do
    r = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge test",
      judge_model: "gpt-4.1", criteria: criteria, status: "completed"
    )
    r.responses.create!(input_data: nil, response_text: "A good summary")
    r
  end

  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")

    stubs.post("/v1/chat/completions") do
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: "Score: 4\nFeedback: Relevant and well-structured." } }]
      }.to_json]
    end

    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
      original.call(*args, **kwargs) do |builder|
        builder.adapter :test, stubs
      end
    end
  end

  it "creates reviews with scores and feedback, transitions to completed" do
    expect(run.status).to eq("completed")

    run.judge_responses!

    expect(run.reload.status).to eq("completed")

    response = run.responses.first
    expect(response.reviews.count).to eq(1)

    review = response.reviews.first
    expect(review.ai_score).to eq(4.0)
    expect(review.ai_feedback).to include("Relevant")
    expect(review.metric_id).to eq(metric.id)
    expect(review.metric_name).to eq("Relevance")
    expect(review.status).to eq("evaluated")
  end

  it "updates existing reviews on re-judge without duplicating" do
    run.judge_responses!
    expect(run.responses.first.reviews.count).to eq(1)

    stubs.post("/v1/chat/completions") do
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: "Score: 5\nFeedback: Excellent work." } }]
      }.to_json]
    end

    run.judge_responses!

    response = run.responses.first
    expect(response.reviews.count).to eq(1)
    expect(response.reviews.first.ai_score).to eq(5.0)
    expect(response.reviews.first.ai_feedback).to include("Excellent")
  end
end
```

- [ ] **Step 2: Run test**

Run: `bundle exec rspec spec/integration/completion_kit/judging_pipeline_spec.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/completion_kit/judging_pipeline_spec.rb
git commit -m "test: end-to-end judging pipeline with re-judge verification"
```

---

### Task 11: Status transitions and failure handling test

**Files:**
- Test: `spec/integration/completion_kit/status_transitions_spec.rb`

- [ ] **Step 1: Write the test**

Create `spec/integration/completion_kit/status_transitions_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Run status transitions", type: :model do
  let(:prompt) { create(:completion_kit_prompt, llm_model: "gpt-4.1") }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  before do
    CompletionKit::ProviderCredential.create!(provider: "openai", api_key: "test-key-123")

    allow(Faraday).to receive(:new).and_wrap_original do |original, *args, **kwargs, &_block|
      original.call(*args, **kwargs) do |builder|
        builder.adapter :test, stubs
      end
    end
  end

  it "pending -> generating -> completed (no judge)" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "No judge")

    stubs.post("/v1/chat/completions") do
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: "output" } }]
      }.to_json]
    end

    run.generate_responses!
    expect(run.reload.status).to eq("completed")
  end

  it "pending -> generating -> judging -> completed (with judge)" do
    metric = create(:completion_kit_metric)
    criteria = create(:completion_kit_criteria)
    CompletionKit::CriteriaMembership.create!(criteria: criteria, metric: metric, position: 1)

    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "With judge",
      judge_model: "gpt-4.1", criteria: criteria
    )

    call_count = 0
    stubs.post("/v1/chat/completions") do
      call_count += 1
      content = if call_count == 1
                  "Generated output"
                else
                  "Score: 4\nFeedback: Good"
                end
      [200, { "Content-Type" => "application/json" }, {
        choices: [{ message: { content: content } }]
      }.to_json]
    end

    run.generate_responses!
    expect(run.reload.status).to eq("completed")
    expect(run.responses.first.reviews.count).to eq(1)
  end

  it "sets status to failed on generation error" do
    run = CompletionKit::Run.create!(prompt: prompt, dataset: nil, name: "Fail test")

    stubs.post("/v1/chat/completions") do
      raise Faraday::ConnectionFailed, "Connection refused"
    end

    result = run.generate_responses!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end

  it "sets status to failed on judging error" do
    metric = create(:completion_kit_metric)
    criteria = create(:completion_kit_criteria)
    CompletionKit::CriteriaMembership.create!(criteria: criteria, metric: metric, position: 1)

    run = CompletionKit::Run.create!(
      prompt: prompt, dataset: nil, name: "Judge fail",
      judge_model: "gpt-4.1", criteria: criteria, status: "completed"
    )
    run.responses.create!(input_data: nil, response_text: "Some output")

    stubs.post("/v1/chat/completions") do
      raise Faraday::ConnectionFailed, "Connection refused"
    end

    result = run.judge_responses!
    expect(result).to be false
    expect(run.reload.status).to eq("failed")
  end
end
```

- [ ] **Step 2: Run test**

Run: `bundle exec rspec spec/integration/completion_kit/status_transitions_spec.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add spec/integration/completion_kit/status_transitions_spec.rb
git commit -m "test: verify run status transitions and failure handling"
```

---

### Task 12: Results and scoring verification test

**Files:**
- Test: `spec/models/completion_kit/scoring_spec.rb`

- [ ] **Step 1: Write the test**

Create `spec/models/completion_kit/scoring_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "Results and scoring", type: :model do
  let(:run) { create(:completion_kit_run) }
  let(:metric1) { create(:completion_kit_metric, name: "Relevance") }
  let(:metric2) { create(:completion_kit_metric, name: "Clarity") }

  let!(:r1) do
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: resp, metric: metric1, ai_score: 4.0, metric_name: "Relevance")
    create(:completion_kit_review, response: resp, metric: metric2, ai_score: 3.0, metric_name: "Clarity")
    resp
  end

  let!(:r2) do
    resp = create(:completion_kit_response, run: run)
    create(:completion_kit_review, response: resp, metric: metric1, ai_score: 5.0, metric_name: "Relevance")
    create(:completion_kit_review, response: resp, metric: metric2, ai_score: 2.0, metric_name: "Clarity")
    resp
  end

  describe "Response#score" do
    it "returns average of review scores" do
      expect(r1.score).to eq(3.5)
      expect(r2.score).to eq(3.5)
    end
  end

  describe "Response#reviewed?" do
    it "returns true when reviews with scores exist" do
      expect(r1.reviewed?).to be true
    end

    it "returns false with no reviews" do
      empty = create(:completion_kit_response, run: run)
      expect(empty.reviewed?).to be false
    end
  end

  describe "Run#avg_score" do
    it "returns average across all responses" do
      expect(run.avg_score).to eq(3.5)
    end
  end

  describe "Run#metric_averages" do
    it "returns per-metric averages" do
      avgs = run.metric_averages
      relevance = avgs.find { |m| m[:name] == "Relevance" }
      clarity = avgs.find { |m| m[:name] == "Clarity" }

      expect(relevance[:avg]).to eq(4.5)
      expect(clarity[:avg]).to eq(2.5)
    end
  end
end
```

- [ ] **Step 2: Run test**

Run: `bundle exec rspec spec/models/completion_kit/scoring_spec.rb`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add spec/models/completion_kit/scoring_spec.rb
git commit -m "test: verify scoring calculations across responses and metrics"
```

---

### Task 13: Run full test suite and final commit

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec`
Expected: All tests pass

- [ ] **Step 2: Fix any failures discovered during audit**

If any tests fail, fix the underlying code (not the tests). The audit is about finding real bugs.

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve issues found during feature audit"
```
