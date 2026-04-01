# OpenAI Model Registry & Responses API Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persistent database-backed model registry with probing, plus migrate OpenAI generation from Chat Completions to Responses API.

**Architecture:** New `completion_kit_models` table stores discovered models with probe results. `ModelDiscoveryService` discovers from OpenAI API, probes each model, persists results. Forms query the DB instead of calling APIs. OpenAiClient switches from `/v1/chat/completions` to `/v1/responses`.

**Tech Stack:** Rails 7, RSpec, Faraday, SQLite/Postgres

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `db/migrate/20260329000001_create_completion_kit_models.rb` | Create | Migration for models registry table |
| `app/models/completion_kit/model.rb` | Create | ActiveRecord model for registry entries |
| `app/services/completion_kit/model_discovery_service.rb` | Create | Discovers, reconciles, and probes models |
| `app/services/completion_kit/open_ai_client.rb` | Modify | Switch to Responses API |
| `app/models/completion_kit/provider_credential.rb` | Modify | Trigger discovery after save |
| `app/controllers/completion_kit/provider_credentials_controller.rb` | Modify | Add refresh action |
| `app/views/completion_kit/prompts/_form.html.erb` | Modify | Read from Model registry |
| `app/views/completion_kit/runs/_form.html.erb` | Modify | Read from Model registry |
| `app/helpers/completion_kit/application_helper.rb` | Modify | Update `ck_grouped_models` for retired models |
| `app/services/completion_kit/api_config.rb` | Modify | Use registry for available_models |
| `spec/rails_helper.rb` | Modify | Add models table to test schema |
| `spec/services/completion_kit/model_discovery_service_spec.rb` | Create | Tests for discovery, reconciliation, probing |
| `spec/models/completion_kit/model_spec.rb` | Create | Model validations and scopes |
| `spec/services/completion_kit/provider_clients_spec.rb` | Modify | Update OpenAI tests for Responses API |

---

### Task 1: Migration and Model

**Files:**
- Create: `db/migrate/20260329000001_create_completion_kit_models.rb`
- Create: `app/models/completion_kit/model.rb`
- Modify: `spec/rails_helper.rb`
- Create: `spec/models/completion_kit/model_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/models/completion_kit/model_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe CompletionKit::Model, type: :model do
  it "validates presence of provider, model_id, and status" do
    model = described_class.new
    expect(model).not_to be_valid
    expect(model.errors[:provider]).to be_present
    expect(model.errors[:model_id]).to be_present
    expect(model.errors[:status]).to be_present
  end

  it "validates uniqueness of model_id scoped to provider" do
    described_class.create!(provider: "openai", model_id: "gpt-4o-mini", status: "active")
    duplicate = described_class.new(provider: "openai", model_id: "gpt-4o-mini", status: "active")
    expect(duplicate).not_to be_valid
  end

  it "validates status inclusion" do
    model = described_class.new(provider: "openai", model_id: "gpt-x", status: "bogus")
    expect(model).not_to be_valid
  end

  describe "scopes" do
    before do
      described_class.create!(provider: "openai", model_id: "gpt-gen", status: "active", supports_generation: true, supports_judging: false)
      described_class.create!(provider: "openai", model_id: "gpt-judge", status: "active", supports_generation: true, supports_judging: true)
      described_class.create!(provider: "openai", model_id: "gpt-retired", status: "retired", supports_generation: true, supports_judging: true)
      described_class.create!(provider: "openai", model_id: "gpt-failed", status: "failed", supports_generation: false, supports_judging: false)
    end

    it ".for_generation returns active models that support generation" do
      ids = described_class.for_generation.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-gen", "gpt-judge")
    end

    it ".for_judging returns active models that support judging" do
      ids = described_class.for_judging.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-judge")
    end

    it ".active returns only active models" do
      ids = described_class.active.pluck(:model_id)
      expect(ids).to contain_exactly("gpt-gen", "gpt-judge")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/model_spec.rb`

Expected: FAIL — table and class don't exist.

- [ ] **Step 3: Add the table to the test schema**

In `spec/rails_helper.rb`, add after the `completion_kit_reviews` table block:

```ruby
  create_table :completion_kit_models, force: true do |t|
    t.string :provider, null: false
    t.string :model_id, null: false
    t.string :display_name
    t.string :status, null: false
    t.boolean :supports_generation
    t.boolean :supports_judging
    t.text :generation_error
    t.text :judging_error
    t.datetime :probed_at
    t.datetime :discovered_at
    t.datetime :retired_at
    t.timestamps
  end
```

- [ ] **Step 4: Create the migration**

Create `db/migrate/20260329000001_create_completion_kit_models.rb`:

```ruby
class CreateCompletionKitModels < ActiveRecord::Migration[7.1]
  def change
    create_table :completion_kit_models do |t|
      t.string :provider, null: false
      t.string :model_id, null: false
      t.string :display_name
      t.string :status, null: false, default: "active"
      t.boolean :supports_generation
      t.boolean :supports_judging
      t.text :generation_error
      t.text :judging_error
      t.datetime :probed_at
      t.datetime :discovered_at
      t.datetime :retired_at
      t.timestamps
    end

    add_index :completion_kit_models, [:provider, :model_id], unique: true
  end
end
```

- [ ] **Step 5: Create the model**

Create `app/models/completion_kit/model.rb`:

```ruby
module CompletionKit
  class Model < ApplicationRecord
    STATUSES = %w[active retired failed].freeze

    validates :provider, presence: true
    validates :model_id, presence: true, uniqueness: { scope: :provider }
    validates :status, presence: true, inclusion: { in: STATUSES }

    scope :active, -> { where(status: "active") }
    scope :for_generation, -> { active.where(supports_generation: true) }
    scope :for_judging, -> { active.where(supports_judging: true) }
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/completion_kit/model_spec.rb`

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20260329000001_create_completion_kit_models.rb app/models/completion_kit/model.rb spec/models/completion_kit/model_spec.rb spec/rails_helper.rb
git commit -m "add completion_kit_models table and Model class with scopes"
```

---

### Task 2: Migrate OpenAiClient to Responses API

**Files:**
- Modify: `app/services/completion_kit/open_ai_client.rb`
- Modify: `spec/services/completion_kit/provider_clients_spec.rb`

- [ ] **Step 1: Write the failing test**

In `spec/services/completion_kit/provider_clients_spec.rb`, replace the first OpenAI test (line 38-59) with:

```ruby
  it "covers OpenAI client success, error, rescue, and configuration branches" do
    client = CompletionKit::OpenAiClient.new(api_key: "openai-key")
    success_request = stub_faraday(faraday_response(success: true, body: {
      output: [{ type: "message", content: [{ type: "output_text", text: " hello " }] }]
    }.to_json))

    expect(client.generate_completion("prompt", model: "gpt-4.1")).to eq("hello")
    expect(success_request.headers["Authorization"]).to eq("Bearer openai-key")
    expect(success_request.path).to eq("/v1/responses")
    expect(client.configured?).to eq(true)
    expect(client.configuration_errors).to eq([])

    stub_faraday(faraday_response(success: false, status: 429, body: "rate limited"))
    expect(client.generate_completion("prompt")).to eq("Error: 429 - rate limited")

    allow(Faraday).to receive(:new).and_raise(StandardError, "network down")
    expect(client.generate_completion("prompt")).to eq("Error: network down")

    unconfigured = CompletionKit::OpenAiClient.new
    allow(unconfigured).to receive(:api_key).and_return(nil)
    expect(unconfigured.generate_completion("prompt")).to eq("Error: API key not configured")
    expect(unconfigured.configured?).to eq(false)
    expect(unconfigured.configuration_errors).to include("OpenAI API key is not configured")
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/provider_clients_spec.rb:38`

Expected: FAIL — still using chat completions format.

- [ ] **Step 3: Rewrite OpenAiClient#generate_completion**

Replace the `generate_completion` method in `app/services/completion_kit/open_ai_client.rb`:

```ruby
    def generate_completion(prompt, options = {})
      return "Error: API key not configured" unless configured?

      require "faraday"
      require "faraday/retry"
      require "json"

      model = options[:model] || "gpt-4.1-mini"
      max_tokens = options[:max_tokens] || 1000
      temperature = options[:temperature] || 0.7

      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 2, interval: 0.5
        f.adapter Faraday.default_adapter
      end

      response = conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.body = {
          model: model,
          input: prompt,
          instructions: "You are a helpful assistant.",
          max_output_tokens: max_tokens,
          temperature: temperature,
          store: false
        }.to_json
      end

      if response.success?
        data = JSON.parse(response.body)
        data["output"][0]["content"][0]["text"].strip
      else
        "Error: #{response.status} - #{response.body}"
      end
    rescue Faraday::Error => e
      raise
    rescue => e
      "Error: #{e.message}"
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/provider_clients_spec.rb`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/open_ai_client.rb spec/services/completion_kit/provider_clients_spec.rb
git commit -m "migrate OpenAI client from Chat Completions to Responses API"
```

---

### Task 3: ModelDiscoveryService

**Files:**
- Create: `app/services/completion_kit/model_discovery_service.rb`
- Create: `spec/services/completion_kit/model_discovery_service_spec.rb`

- [ ] **Step 1: Write the failing tests**

Create `spec/services/completion_kit/model_discovery_service_spec.rb`:

```ruby
require "rails_helper"
require "faraday"
require "json"

RSpec.describe CompletionKit::ModelDiscoveryService, type: :service do
  let(:config) { { provider: "openai", api_key: "test-key" } }

  def faraday_response(success:, body:, status: 200)
    instance_double("Faraday::Response", success?: success, body: body, status: status)
  end

  def stub_faraday_get(response)
    request = Struct.new(:headers).new({})
    allow(Faraday).to receive(:get).and_yield(request).and_return(response)
    request
  end

  def stub_faraday_post(response)
    request_class = Struct.new(:headers, :body, :path, keyword_init: true) do
      def url(value); self.path = value; end
    end
    request = request_class.new(headers: {})
    builder = instance_double("Faraday::RackBuilder")
    connection = instance_double("Faraday::Connection")
    allow(builder).to receive(:request)
    allow(builder).to receive(:adapter)
    allow(connection).to receive(:post).and_yield(request).and_return(response)
    allow(Faraday).to receive(:new).and_yield(builder).and_return(connection)
    request
  end

  describe "#refresh!" do
    it "discovers new models and creates them as active" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [
          { id: "gpt-4.1-mini", object: "model" },
          { id: "gpt-5.4-mini", object: "model" }
        ] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "Score: 4\nFeedback: Good" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.count).to eq(2)
      model = CompletionKit::Model.find_by(model_id: "gpt-4.1-mini")
      expect(model.status).to eq("active")
      expect(model.provider).to eq("openai")
      expect(model.supports_generation).to eq(true)
      expect(model.discovered_at).to be_present
      expect(model.probed_at).to be_present
    end

    it "retires models that disappear from the API" do
      CompletionKit::Model.create!(provider: "openai", model_id: "gpt-old", status: "active", discovered_at: 1.day.ago)

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-old")
      expect(model.status).to eq("retired")
      expect(model.retired_at).to be_present
    end

    it "does not re-probe existing models" do
      CompletionKit::Model.create!(
        provider: "openai", model_id: "gpt-4.1-mini", status: "active",
        supports_generation: true, supports_judging: true, probed_at: 1.hour.ago, discovered_at: 1.day.ago
      )

      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-4.1-mini", object: "model" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      expect(CompletionKit::Model.count).to eq(1)
      expect(CompletionKit::Model.first.probed_at).to be < 1.minute.ago
    end

    it "marks generation as failed when probe returns error" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-broken", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: false,
        status: 404,
        body: '{"error":{"message":"model not found"}}'
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-broken")
      expect(model.supports_generation).to eq(false)
      expect(model.generation_error).to include("404")
      expect(model.status).to eq("failed")
    end

    it "marks judging as failed when probe response is not parseable" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "gpt-nojudge", object: "model" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { output: [{ type: "message", content: [{ type: "output_text", text: "I refuse to score things" }] }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "gpt-nojudge")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(false)
      expect(model.judging_error).to be_present
      expect(model.status).to eq("active")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`

Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement ModelDiscoveryService**

Create `app/services/completion_kit/model_discovery_service.rb`:

```ruby
require "faraday"
require "faraday/retry"
require "json"

module CompletionKit
  class ModelDiscoveryService
    def initialize(config:)
      @provider = config[:provider]
      @api_key = config[:api_key]
    end

    def refresh!
      api_model_ids = fetch_model_ids
      reconcile(api_model_ids)
      probe_new_models
    end

    private

    def fetch_model_ids
      response = Faraday.get("https://api.openai.com/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end

      return [] unless response.success?

      JSON.parse(response.body).fetch("data", []).map { |entry| entry["id"] }
    rescue StandardError
      []
    end

    def reconcile(api_model_ids)
      existing = Model.where(provider: @provider).index_by(&:model_id)

      api_model_ids.each do |model_id|
        if existing[model_id]
          existing[model_id].update!(status: "active", retired_at: nil) if existing[model_id].status == "retired"
        else
          Model.create!(
            provider: @provider,
            model_id: model_id,
            status: "active",
            discovered_at: Time.current
          )
        end
      end

      active_not_in_api = Model.where(provider: @provider, status: "active")
                               .where.not(model_id: api_model_ids)
      active_not_in_api.update_all(status: "retired", retired_at: Time.current)
    end

    def probe_new_models
      Model.where(provider: @provider, supports_generation: nil).find_each do |model|
        probe_generation(model)
        probe_judging(model) if model.supports_generation
        model.probed_at = Time.current
        model.status = "failed" if model.supports_generation == false
        model.save!
      end
    end

    def probe_generation(model)
      response = responses_api_call(model.model_id, "Say hello", max_output_tokens: 10)

      if response.success?
        data = JSON.parse(response.body)
        text = data.dig("output", 0, "content", 0, "text")
        if text.present?
          model.supports_generation = true
        else
          model.supports_generation = false
          model.generation_error = "Empty response"
        end
      else
        model.supports_generation = false
        model.generation_error = "#{response.status} - #{response.body.truncate(500)}"
      end
    rescue StandardError => e
      model.supports_generation = false
      model.generation_error = e.message
    end

    def probe_judging(model)
      judge_input = <<~PROMPT
        You are an expert evaluator. You MUST respond with ONLY two lines in this exact format, nothing else:

        Score: <integer from 1 to 5>
        Feedback: <one sentence explaining why>

        AI output to evaluate: The sky is blue.
      PROMPT

      response = responses_api_call(model.model_id, judge_input, max_output_tokens: 50)

      if response.success?
        data = JSON.parse(response.body)
        text = data.dig("output", 0, "content", 0, "text").to_s
        if text.match?(/Score:\s*\d/i)
          model.supports_judging = true
        else
          model.supports_judging = false
          model.judging_error = "Response not in Score/Feedback format: #{text.truncate(200)}"
        end
      else
        model.supports_judging = false
        model.judging_error = "#{response.status} - #{response.body.truncate(500)}"
      end
    rescue StandardError => e
      model.supports_judging = false
      model.judging_error = e.message
    end

    def responses_api_call(model_id, input, max_output_tokens: 10)
      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end

      conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.body = {
          model: model_id,
          input: input,
          max_output_tokens: max_output_tokens,
          store: false
        }.to_json
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/model_discovery_service.rb spec/services/completion_kit/model_discovery_service_spec.rb
git commit -m "add ModelDiscoveryService with discovery, reconciliation, and probing"
```

---

### Task 4: Trigger discovery from ProviderCredential

**Files:**
- Modify: `app/models/completion_kit/provider_credential.rb`
- Modify: `app/controllers/completion_kit/provider_credentials_controller.rb`

- [ ] **Step 1: Add after_save callback to ProviderCredential**

In `app/models/completion_kit/provider_credential.rb`, add after the validations:

```ruby
    after_save :refresh_models

    private

    def refresh_models
      return unless provider == "openai"
      ModelDiscoveryService.new(config: config_hash).refresh!
    rescue StandardError
    end
```

Make `refresh_models` private by placing it after the existing private methods or by adding it in the private section. Note: the existing model doesn't have an explicit `private` keyword before its methods — add the callback after the `validates` line and add the private method at the bottom of the class before the final `end`.

- [ ] **Step 2: Add refresh action to controller**

In `app/controllers/completion_kit/provider_credentials_controller.rb`, add to `before_action`:

```ruby
    before_action :set_provider_credential, only: [:edit, :update, :refresh]
```

And add the action:

```ruby
    def refresh
      ModelDiscoveryService.new(config: @provider_credential.config_hash).refresh!
      redirect_to provider_credentials_path, notice: "Models refreshed."
    end
```

- [ ] **Step 3: Add the route**

Check the routes file and add a member route for refresh. Find the routes file:

In `config/routes.rb` (inside the engine's routes), add `post :refresh, on: :member` to the `provider_credentials` resource.

- [ ] **Step 4: Run full test suite**

Run: `bundle exec rspec spec/`

Expected: all pass (the callback fires but discovery is a no-op without real API).

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/provider_credential.rb app/controllers/completion_kit/provider_credentials_controller.rb config/routes.rb
git commit -m "trigger model discovery on provider credential save, add refresh action"
```

---

### Task 5: Wire forms to read from Model registry

**Files:**
- Modify: `app/views/completion_kit/prompts/_form.html.erb`
- Modify: `app/views/completion_kit/runs/_form.html.erb`
- Modify: `app/helpers/completion_kit/application_helper.rb`
- Modify: `app/services/completion_kit/api_config.rb`

- [ ] **Step 1: Update ApiConfig.available_models to use registry**

In `app/services/completion_kit/api_config.rb`, replace the `available_models` method:

```ruby
    def self.available_models(provider: nil, scope: :generation)
      query = case scope
              when :judging then Model.for_judging
              when :generation then Model.for_generation
              else Model.active
              end
      query = query.where(provider: provider) if provider.present?
      query.order(:provider, :display_name).map do |m|
        { id: m.model_id, name: m.display_name || m.model_id, provider: m.provider }
      end
    end
```

- [ ] **Step 2: Update ck_grouped_models to handle retired models**

In `app/helpers/completion_kit/application_helper.rb`, update `ck_grouped_models`:

```ruby
    def ck_grouped_models(models, selected = nil)
      if selected.present? && models.none? { |m| m[:id] == selected }
        retired = CompletionKit::Model.find_by(model_id: selected)
        if retired
          models = models + [{ id: retired.model_id, name: "#{retired.display_name || retired.model_id} (retired)", provider: retired.provider }]
        end
      end
      groups = models.group_by { |m| m[:provider] }.map do |provider, ms|
        [ck_provider_label(provider), ms.map { |m| [m[:name], m[:id]] }]
      end
      grouped_options_for_select(groups, selected)
    end
```

- [ ] **Step 3: Update prompt form to use generation scope**

In `app/views/completion_kit/prompts/_form.html.erb`, change line 32:

From:
```erb
      <% available = CompletionKit::Prompt.available_models %>
```

To:
```erb
      <% available = CompletionKit::ApiConfig.available_models(scope: :generation) %>
```

- [ ] **Step 4: Update run form to use judging scope for judge model**

In `app/views/completion_kit/runs/_form.html.erb`, change line 35:

From:
```erb
      <% available = CompletionKit::Prompt.available_models %>
```

To:
```erb
      <% available = CompletionKit::ApiConfig.available_models(scope: :judging) %>
```

- [ ] **Step 5: Run full test suite**

Run: `bundle exec rspec spec/`

Expected: all pass. Some tests may need updating if they assert on `available_models` output.

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/api_config.rb app/helpers/completion_kit/application_helper.rb app/views/completion_kit/prompts/_form.html.erb app/views/completion_kit/runs/_form.html.erb
git commit -m "wire forms to read from model registry instead of runtime API calls"
```

---

### Task 6: Install migration in standalone app and test end-to-end

**Files:** None new — verification only.

- [ ] **Step 1: Install and run migration**

```bash
cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate
```

- [ ] **Step 2: Run full test suite**

```bash
cd /Users/damien/Work/homemade/completion-kit && bundle exec rspec spec/
```

Expected: all pass, 100% coverage.

- [ ] **Step 3: Test in browser**

1. Navigate to Settings, edit OpenAI provider credential, save — should trigger discovery
2. Check the prompt form — dropdown should show only generation-capable models
3. Check the run form — judge dropdown should show only judging-capable models
4. Verify no models like `gpt-5.4-pro` appear

- [ ] **Step 4: Commit any fixes**

```bash
git add -A && git commit -m "end-to-end verification of model registry"
```
