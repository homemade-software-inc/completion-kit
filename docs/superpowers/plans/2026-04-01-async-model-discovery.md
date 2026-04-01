# Async Model Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move model discovery from a blocking after_save callback to a background job with real-time progress via Turbo Streams.

**Architecture:** Add discovery progress columns to ProviderCredential. Replace the sync `refresh_models` callback with `enqueue_discovery` which queues a `ModelDiscoveryJob`. The job updates progress columns and broadcasts via Turbo Streams. A reusable `_discovery_status` partial renders on the provider credentials index, form, and model select fields.

**Tech Stack:** Rails 8.1, ActiveJob, Turbo Streams, RSpec

---

## File Structure

```
db/migrate/TIMESTAMP_add_discovery_columns_to_provider_credentials.rb  — migration
app/models/completion_kit/provider_credential.rb                        — modify: callback + broadcasts
app/jobs/completion_kit/model_discovery_job.rb                          — create: background job
app/services/completion_kit/model_discovery_service.rb                  — modify: progress callback
app/views/completion_kit/provider_credentials/_discovery_status.html.erb — create: reusable partial
app/views/completion_kit/provider_credentials/index.html.erb            — modify: add status partial
app/views/completion_kit/provider_credentials/_form.html.erb            — modify: add status partial
app/views/completion_kit/prompts/_form.html.erb                         — modify: add status partial
app/views/completion_kit/runs/_form.html.erb                            — modify: add status partial
spec/models/completion_kit/provider_credential_spec.rb                  — modify: update callback tests
spec/jobs/completion_kit/model_discovery_job_spec.rb                    — create
spec/services/completion_kit/model_discovery_service_spec.rb            — modify: progress callback tests
```

---

### Task 1: Migration — add discovery columns to provider_credentials

**Files:**
- Create: `db/migrate/TIMESTAMP_add_discovery_columns_to_provider_credentials.rb`

- [ ] **Step 1: Generate the migration**

Run: `cd /Users/damien/Work/homemade/completion-kit && bundle exec rails generate migration AddDiscoveryColumnsToCompletionKitProviderCredentials discovery_status:string discovery_current:integer discovery_total:integer --no-comments`

- [ ] **Step 2: Edit the migration to add defaults**

The generated migration should look like:

```ruby
class AddDiscoveryColumnsToCompletionKitProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :completion_kit_provider_credentials, :discovery_status, :string
    add_column :completion_kit_provider_credentials, :discovery_current, :integer, default: 0
    add_column :completion_kit_provider_credentials, :discovery_total, :integer, default: 0
  end
end
```

- [ ] **Step 3: Run the migration**

Run: `bundle exec rails db:migrate`
Expected: migration applies successfully

- [ ] **Step 4: Install migration into standalone**

Run: `cd standalone && bin/rails completion_kit:install:migrations && bin/rails db:migrate`

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*discovery* spec/dummy/db/schema.rb standalone/db/migrate/*discovery* standalone/db/schema.rb
git commit -m "db: add discovery progress columns to provider_credentials"
```

---

### Task 2: ModelDiscoveryService — add progress callback

**Files:**
- Modify: `app/services/completion_kit/model_discovery_service.rb`
- Create: `spec/services/completion_kit/model_discovery_service_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/completion_kit/model_discovery_service_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::ModelDiscoveryService do
  let(:config) { { provider: "openai", api_key: "test-key" } }
  let(:service) { described_class.new(config: config) }

  describe "#refresh!" do
    before do
      allow(service).to receive(:fetch_models).and_return([])
    end

    it "accepts an optional progress block" do
      expect { service.refresh! { |current, total| } }.not_to raise_error
    end
  end

  describe "progress callback during probing" do
    before do
      allow(service).to receive(:fetch_models).and_return([
        { id: "gpt-test-1", display_name: nil },
        { id: "gpt-test-2", display_name: nil }
      ])
      allow(service).to receive(:send_probe).and_return(
        instance_double(Faraday::Response, success?: false, body: "error", status: 400)
      )
    end

    it "yields current count and total after each model probe" do
      progress_updates = []
      service.refresh! { |current, total| progress_updates << [current, total] }
      expect(progress_updates).to eq([[1, 2], [2, 2]])
    end

    it "works without a block" do
      expect { service.refresh! }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`
Expected: FAIL — wrong number of arguments or no yield

- [ ] **Step 3: Modify the service to accept and call the progress block**

In `app/services/completion_kit/model_discovery_service.rb`, change `refresh!` and `probe_new_models`:

```ruby
def refresh!(&on_progress)
  models_with_names = fetch_models
  reconcile(models_with_names)
  probe_new_models(&on_progress)
end
```

And change `probe_new_models` to:

```ruby
def probe_new_models(&on_progress)
  unprobed = Model.where(provider: @provider, supports_generation: nil, status: "active")
  total = unprobed.count
  current = 0
  unprobed.find_each do |model|
    probe_generation(model)
    probe_judging(model) if model.supports_generation
    model.probed_at = Time.current
    model.status = "failed" if model.supports_generation == false
    model.save!
    current += 1
    on_progress&.call(current, total)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/model_discovery_service.rb spec/services/completion_kit/model_discovery_service_spec.rb
git commit -m "feat: add progress callback to ModelDiscoveryService"
```

---

### Task 3: ModelDiscoveryJob

**Files:**
- Create: `app/jobs/completion_kit/model_discovery_job.rb`
- Create: `spec/jobs/completion_kit/model_discovery_job_spec.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# spec/jobs/completion_kit/model_discovery_job_spec.rb
require "rails_helper"

RSpec.describe CompletionKit::ModelDiscoveryJob, type: :job do
  let!(:credential) { create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test") }

  before do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)
  end

  it "sets discovery_status to discovering then completed" do
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_status).to eq("completed")
  end

  it "updates discovery_current via the progress callback" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_yield(3, 10)
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_current).to eq(3)
    expect(credential.discovery_total).to eq(10)
  end

  it "sets discovery_status to failed on error" do
    allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!).and_raise(StandardError, "boom")
    described_class.perform_now(credential.id)
    credential.reload
    expect(credential.discovery_status).to eq("failed")
  end

  it "does nothing if credential not found" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/jobs/completion_kit/model_discovery_job_spec.rb`
Expected: FAIL — uninitialized constant

- [ ] **Step 3: Implement the job**

```ruby
# app/jobs/completion_kit/model_discovery_job.rb
module CompletionKit
  class ModelDiscoveryJob < ApplicationJob
    queue_as :default

    def perform(provider_credential_id)
      credential = ProviderCredential.find_by(id: provider_credential_id)
      return unless credential

      credential.update_columns(discovery_status: "discovering", discovery_current: 0, discovery_total: 0)
      credential.broadcast_discovery_progress

      service = ModelDiscoveryService.new(config: credential.config_hash)
      service.refresh! do |current, total|
        credential.update_columns(discovery_current: current, discovery_total: total)
        credential.broadcast_discovery_progress
      end

      credential.update_columns(discovery_status: "completed")
      credential.broadcast_discovery_complete
    rescue StandardError
      credential&.update_columns(discovery_status: "failed")
      credential&.broadcast_discovery_progress
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/completion_kit/model_discovery_job_spec.rb`
Expected: FAIL — `broadcast_discovery_progress` not defined yet (this is expected, we'll add it in Task 4)

- [ ] **Step 5: Stub the broadcast methods for now**

Add stubs to the test's `before` block:

```ruby
before do
  allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)
  allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_progress)
  allow_any_instance_of(CompletionKit::ProviderCredential).to receive(:broadcast_discovery_complete)
end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bundle exec rspec spec/jobs/completion_kit/model_discovery_job_spec.rb`
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add app/jobs/completion_kit/model_discovery_job.rb spec/jobs/completion_kit/model_discovery_job_spec.rb
git commit -m "feat: add ModelDiscoveryJob for async model discovery"
```

---

### Task 4: ProviderCredential — replace callback + add broadcasts

**Files:**
- Modify: `app/models/completion_kit/provider_credential.rb`
- Modify: `spec/models/completion_kit/provider_credential_spec.rb`

- [ ] **Step 1: Update the model**

In `app/models/completion_kit/provider_credential.rb`:

1. Add `include Turbo::Broadcastable` after the class opening
2. Replace `after_save :refresh_models` with `after_save :enqueue_discovery`
3. Replace the `refresh_models` private method with:

```ruby
def enqueue_discovery
  ModelDiscoveryJob.perform_later(id)
end

def broadcast_discovery_progress
  broadcast_replace_to(
    "completion_kit_provider_#{id}",
    target: "discovery_status_#{id}",
    html: render_partial("completion_kit/provider_credentials/discovery_status", provider_credential: self)
  )
end

def broadcast_discovery_complete
  broadcast_discovery_progress
  ProviderCredential.find_each do |cred|
    cred.broadcast_replace_to(
      "completion_kit_provider_#{cred.id}",
      target: "discovery_status_#{cred.id}",
      html: render_partial("completion_kit/provider_credentials/discovery_status", provider_credential: cred)
    )
  end
end

def render_partial(partial, locals)
  CompletionKit::ApplicationController.render(partial: partial, locals: locals)
end
```

- [ ] **Step 2: Update existing tests**

In `spec/models/completion_kit/provider_credential_spec.rb`:

Change the `before` block at the top from:
```ruby
before do
  allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)
end
```
to:
```ruby
before do
  allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
end
```

Replace the `#refresh_models (after_save callback)` describe block with:

```ruby
describe "#enqueue_discovery (after_save callback)" do
  it "enqueues ModelDiscoveryJob on save" do
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(kind_of(Integer))
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
  end

  it "enqueues for all providers" do
    expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(kind_of(Integer))
    create(:completion_kit_provider_credential, provider: "anthropic", api_key: "sk-test")
  end
end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/completion_kit/provider_credential_spec.rb`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add app/models/completion_kit/provider_credential.rb spec/models/completion_kit/provider_credential_spec.rb
git commit -m "feat: replace sync refresh_models with async enqueue_discovery"
```

---

### Task 5: Discovery status partial

**Files:**
- Create: `app/views/completion_kit/provider_credentials/_discovery_status.html.erb`

- [ ] **Step 1: Create the partial**

```erb
<div id="discovery_status_<%= provider_credential.id %>">
  <% if provider_credential.discovery_status == "discovering" %>
    <div class="ck-discovery-bar">
      <div class="ck-discovery-bar__label">
        Discovering models&hellip;
        <% if provider_credential.discovery_total > 0 %>
          <%= provider_credential.discovery_current %>/<%= provider_credential.discovery_total %>
        <% end %>
      </div>
      <% if provider_credential.discovery_total > 0 %>
        <div class="ck-discovery-bar__track">
          <div class="ck-discovery-bar__fill" style="width: <%= (provider_credential.discovery_current.to_f / provider_credential.discovery_total * 100).round %>%"></div>
        </div>
      <% else %>
        <div class="ck-discovery-bar__track">
          <div class="ck-discovery-bar__fill ck-discovery-bar__fill--indeterminate"></div>
        </div>
      <% end %>
    </div>
  <% elsif provider_credential.discovery_status == "failed" %>
    <div class="ck-discovery-bar ck-discovery-bar--failed">
      <div class="ck-discovery-bar__label">Model discovery failed</div>
    </div>
  <% elsif provider_credential.discovery_status == "completed" %>
    <div class="ck-discovery-bar ck-discovery-bar--completed">
      <div class="ck-discovery-bar__label">Models updated</div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Add CSS for the discovery bar**

Append to `app/assets/stylesheets/completion_kit/application.css`:

```css
.ck-discovery-bar {
  padding: 0.5rem 0;
  font-size: 0.8rem;
  color: var(--ck-muted);
}

.ck-discovery-bar__label {
  margin-bottom: 0.25rem;
  font-family: var(--ck-mono);
}

.ck-discovery-bar__track {
  height: 4px;
  background: var(--ck-surface);
  border-radius: 2px;
  overflow: hidden;
}

.ck-discovery-bar__fill {
  height: 100%;
  background: var(--ck-accent);
  border-radius: 2px;
  transition: width 0.3s ease;
}

.ck-discovery-bar__fill--indeterminate {
  width: 30%;
  animation: ck-indeterminate 1.5s infinite ease-in-out;
}

@keyframes ck-indeterminate {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(400%); }
}

.ck-discovery-bar--failed .ck-discovery-bar__label {
  color: var(--ck-danger);
}

.ck-discovery-bar--completed .ck-discovery-bar__label {
  color: var(--ck-success);
}
```

- [ ] **Step 3: Commit**

```bash
git add app/views/completion_kit/provider_credentials/_discovery_status.html.erb app/assets/stylesheets/completion_kit/application.css
git commit -m "ui: add discovery status partial and CSS"
```

---

### Task 6: Wire up discovery status in views

**Files:**
- Modify: `app/views/completion_kit/provider_credentials/index.html.erb`
- Modify: `app/views/completion_kit/provider_credentials/_form.html.erb`
- Modify: `app/views/completion_kit/prompts/_form.html.erb`
- Modify: `app/views/completion_kit/runs/_form.html.erb`

- [ ] **Step 1: Add Turbo Stream subscription and status partial to provider credentials index**

In `app/views/completion_kit/provider_credentials/index.html.erb`, add at the very top (before the `<section>` tag):

```erb
<% @provider_credentials.each do |pc| %>
  <%= turbo_stream_from "completion_kit_provider_#{pc.id}" %>
<% end %>
```

Inside the `<tbody>`, after the `</tr>` for each provider_credential, add a new row:

```erb
<tr>
  <td colspan="7" style="padding: 0; border: none;">
    <%= render "discovery_status", provider_credential: provider_credential %>
  </td>
</tr>
```

- [ ] **Step 2: Add status partial to provider credential form**

In `app/views/completion_kit/provider_credentials/_form.html.erb`, add after the `<div class="ck-actions">...</div>` block but still inside the form:

```erb
<% if provider_credential.persisted? %>
  <%= turbo_stream_from "completion_kit_provider_#{provider_credential.id}" %>
  <%= render "discovery_status", provider_credential: provider_credential %>
<% end %>
```

- [ ] **Step 3: Add status partial to prompt form model select**

In `app/views/completion_kit/prompts/_form.html.erb`, after the model select `<div class="ck-select-with-action">...</div>`, add:

```erb
<% CompletionKit::ProviderCredential.find_each do |pc| %>
  <%= turbo_stream_from "completion_kit_provider_#{pc.id}" %>
<% end %>
<% CompletionKit::ProviderCredential.where(discovery_status: "discovering").find_each do |pc| %>
  <%= render "completion_kit/provider_credentials/discovery_status", provider_credential: pc %>
<% end %>
```

- [ ] **Step 4: Add status partial to run form judge model select**

In `app/views/completion_kit/runs/_form.html.erb`, after the judge model `<div class="ck-select-with-action">...</div>`, add:

```erb
<% CompletionKit::ProviderCredential.find_each do |pc| %>
  <%= turbo_stream_from "completion_kit_provider_#{pc.id}" %>
<% end %>
<% CompletionKit::ProviderCredential.where(discovery_status: "discovering").find_each do |pc| %>
  <%= render "completion_kit/provider_credentials/discovery_status", provider_credential: pc %>
<% end %>
```

- [ ] **Step 5: Commit**

```bash
git add app/views/completion_kit/provider_credentials/index.html.erb app/views/completion_kit/provider_credentials/_form.html.erb app/views/completion_kit/prompts/_form.html.erb app/views/completion_kit/runs/_form.html.erb
git commit -m "ui: wire discovery status partial into provider, prompt, and run forms"
```

---

### Task 7: Update controller — remove sync refresh

**Files:**
- Modify: `app/controllers/completion_kit/provider_credentials_controller.rb`
- Modify: `spec/requests/completion_kit/provider_credentials_spec.rb`

- [ ] **Step 1: Update the refresh action to use the job**

In `app/controllers/completion_kit/provider_credentials_controller.rb`, change the `refresh` method:

```ruby
def refresh
  ModelDiscoveryJob.perform_later(@provider_credential.id)
  redirect_to provider_credentials_path, notice: "Model discovery started."
end
```

Change the `refresh_all` method:

```ruby
def refresh_all
  ProviderCredential.find_each do |cred|
    ModelDiscoveryJob.perform_later(cred.id)
  end

  respond_to do |format|
    format.json { render json: { status: "discovery_started" } }
    format.html { redirect_back fallback_location: provider_credentials_path, notice: "Model discovery started." }
  end
end
```

- [ ] **Step 2: Update specs**

In `spec/requests/completion_kit/provider_credentials_spec.rb`, find any specs that test `refresh` or `refresh_all` and update expectations from sync results to checking the job was enqueued. For example:

```ruby
it "enqueues discovery job for refresh" do
  expect(CompletionKit::ModelDiscoveryJob).to receive(:perform_later).with(provider_credential.id)
  post refresh_provider_credential_path(provider_credential)
  expect(response).to redirect_to(provider_credentials_path)
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/requests/completion_kit/provider_credentials_spec.rb`
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add app/controllers/completion_kit/provider_credentials_controller.rb spec/requests/completion_kit/provider_credentials_spec.rb
git commit -m "feat: make refresh actions async via ModelDiscoveryJob"
```

---

### Task 8: Update all affected specs and fix coverage

**Files:**
- Modify: various spec files that stub `ModelDiscoveryService`

- [ ] **Step 1: Find all specs that stub ModelDiscoveryService**

Run: `grep -rl "ModelDiscoveryService" spec/`

Every spec that has `allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)` needs to change to `allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)`.

- [ ] **Step 2: Update each spec file**

Replace all instances of:
```ruby
allow_any_instance_of(CompletionKit::ModelDiscoveryService).to receive(:refresh!)
```
with:
```ruby
allow(CompletionKit::ModelDiscoveryJob).to receive(:perform_later)
```

- [ ] **Step 3: Run the full test suite**

Run: `bundle exec rspec`
Expected: all pass, 100% line and branch coverage

- [ ] **Step 4: Fix any remaining coverage gaps**

If any new code is uncovered, add targeted tests.

- [ ] **Step 5: Commit**

```bash
git add spec/
git commit -m "test: update all specs for async model discovery"
```

---

### Task 9: Install migration into standalone and push

- [ ] **Step 1: Run the full test suite one final time**

Run: `bundle exec rspec`
Expected: all pass, 100% coverage

- [ ] **Step 2: Push**

```bash
git push
```
