# Refresh Models Modal & Multi-Provider Discovery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Anthropic support to ModelDiscoveryService, make refresh_all work for all providers, and add a confirm dialog + loading modal to the refresh button that updates dropdowns in-place when complete.

**Architecture:** Extend ModelDiscoveryService to branch on provider for API calls. Update refresh_all controller to return JSON with counts and rendered options HTML. Replace the refresh button's form submit with JS that shows a confirm, loading modal, fetches JSON, updates the select, and shows completion stats.

**Tech Stack:** Rails 7, Faraday, inline JS, CSS modal

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `app/services/completion_kit/model_discovery_service.rb` | Modify | Add Anthropic discovery + probing |
| `app/controllers/completion_kit/provider_credentials_controller.rb` | Modify | Make refresh_all iterate all providers, return JSON |
| `app/views/completion_kit/prompts/_form.html.erb` | Modify | Replace button_to with JS-driven refresh |
| `app/views/completion_kit/runs/_form.html.erb` | Modify | Same JS-driven refresh for judge model |
| `app/views/layouts/completion_kit/application.html.erb` | Modify | Add modal markup and shared JS function |
| `app/assets/stylesheets/completion_kit/application.css` | Modify | Modal styles |
| `spec/services/completion_kit/model_discovery_service_spec.rb` | Modify | Add Anthropic discovery + probing tests |
| `spec/requests/completion_kit/provider_credentials_spec.rb` | Modify | Test JSON response from refresh_all |

---

### Task 1: Add Anthropic support to ModelDiscoveryService

**Files:**
- Modify: `app/services/completion_kit/model_discovery_service.rb`
- Modify: `spec/services/completion_kit/model_discovery_service_spec.rb`

- [ ] **Step 1: Write the failing tests for Anthropic discovery**

Add a new describe block in `spec/services/completion_kit/model_discovery_service_spec.rb`:

```ruby
  describe "#refresh! for anthropic" do
    let(:config) { { provider: "anthropic", api_key: "anthropic-key" } }

    it "discovers anthropic models and probes them" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [
          { id: "claude-3-7-sonnet-latest", display_name: "Claude 3.7 Sonnet" }
        ] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: true,
        body: { content: [{ type: "text", text: "Score: 5\nFeedback: Great" }] }.to_json
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-3-7-sonnet-latest")
      expect(model.status).to eq("active")
      expect(model.provider).to eq("anthropic")
      expect(model.display_name).to eq("Claude 3.7 Sonnet")
      expect(model.supports_generation).to eq(true)
      expect(model.supports_judging).to eq(true)
      expect(model.probed_at).to be_present
    end

    it "marks anthropic model generation as failed on error" do
      stub_faraday_get(faraday_response(
        success: true,
        body: { data: [{ id: "claude-broken" }] }.to_json
      ))
      stub_faraday_post(faraday_response(
        success: false,
        status: 400,
        body: '{"error":{"message":"bad request"}}'
      ))

      service = described_class.new(config: config)
      service.refresh!

      model = CompletionKit::Model.find_by(model_id: "claude-broken")
      expect(model.supports_generation).to eq(false)
      expect(model.status).to eq("failed")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`

Expected: FAIL — fetch_model_ids calls OpenAI API regardless of provider.

- [ ] **Step 3: Refactor ModelDiscoveryService for multi-provider**

Replace the entire contents of `app/services/completion_kit/model_discovery_service.rb`:

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
      models_with_names = fetch_models
      reconcile(models_with_names)
      probe_new_models
    end

    private

    def fetch_models
      case @provider
      when "openai" then fetch_openai_models
      when "anthropic" then fetch_anthropic_models
      else []
      end
    rescue StandardError
      []
    end

    def fetch_openai_models
      response = Faraday.get("https://api.openai.com/v1/models") do |req|
        req.headers["Authorization"] = "Bearer #{@api_key}"
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: nil } }
    end

    def fetch_anthropic_models
      response = Faraday.get("https://api.anthropic.com/v1/models?limit=100") do |req|
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
      end
      return [] unless response.success?
      JSON.parse(response.body).fetch("data", []).map { |e| { id: e["id"], display_name: e["display_name"] } }
    end

    def reconcile(models_with_names)
      api_model_ids = models_with_names.map { |m| m[:id] }
      names_by_id = models_with_names.each_with_object({}) { |m, h| h[m[:id]] = m[:display_name] }
      existing = Model.where(provider: @provider).index_by(&:model_id)

      api_model_ids.each do |model_id|
        if existing[model_id]
          attrs = { status: "active", retired_at: nil }
          attrs[:display_name] = names_by_id[model_id] if names_by_id[model_id].present?
          existing[model_id].update!(attrs) if existing[model_id].status == "retired" || names_by_id[model_id].present?
        else
          Model.create!(
            provider: @provider,
            model_id: model_id,
            display_name: names_by_id[model_id],
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
      Model.where(provider: @provider, supports_generation: nil, status: "active").find_each do |model|
        probe_generation(model)
        probe_judging(model) if model.supports_generation
        model.probed_at = Time.current
        model.status = "failed" if model.supports_generation == false
        model.save!
      end
    end

    def probe_generation(model)
      response = send_probe(model.model_id, "Say hello", 20)
      if response.success?
        text = extract_text(response)
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

      response = send_probe(model.model_id, judge_input, 50)
      if response.success?
        text = extract_text(response).to_s
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

    def send_probe(model_id, input, max_tokens)
      case @provider
      when "openai" then openai_probe(model_id, input, max_tokens)
      when "anthropic" then anthropic_probe(model_id, input, max_tokens)
      else raise "Unsupported provider: #{@provider}"
      end
    end

    def extract_text(response)
      data = JSON.parse(response.body)
      case @provider
      when "openai"
        data.dig("output", 0, "content", 0, "text")
      when "anthropic"
        data.dig("content", 0, "text")
      end
    end

    def openai_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: "https://api.openai.com") do |f|
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/v1/responses"
        req.headers["Content-Type"] = "application/json"
        req.headers["Authorization"] = "Bearer #{@api_key}"
        req.body = { model: model_id, input: input, max_output_tokens: max_tokens, store: false }.to_json
      end
    end

    def anthropic_probe(model_id, input, max_tokens)
      conn = Faraday.new(url: "https://api.anthropic.com") do |f|
        f.request :retry, max: 1, interval: 0.5
        f.adapter Faraday.default_adapter
      end
      conn.post do |req|
        req.url "/v1/messages"
        req.headers["Content-Type"] = "application/json"
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = "2023-06-01"
        req.body = { model: model_id, messages: [{ role: "user", content: input }], max_tokens: max_tokens }.to_json
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/model_discovery_service_spec.rb`

Expected: all pass.

- [ ] **Step 5: Run full suite**

Run: `bundle exec rspec spec/`

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/services/completion_kit/model_discovery_service.rb spec/services/completion_kit/model_discovery_service_spec.rb
git commit -m "add Anthropic support to ModelDiscoveryService"
```

---

### Task 2: Update refresh_all to iterate all providers and return JSON

**Files:**
- Modify: `app/controllers/completion_kit/provider_credentials_controller.rb`
- Modify: `app/helpers/completion_kit/application_helper.rb`
- Modify: `spec/requests/completion_kit/provider_credentials_spec.rb`

- [ ] **Step 1: Add a helper method for rendering model options as HTML string**

In `app/helpers/completion_kit/application_helper.rb`, add after `ck_grouped_models`:

```ruby
    def ck_model_options_html(scope)
      models = CompletionKit::ApiConfig.available_models(scope: scope)
      return "" if models.empty?
      ck_grouped_models(models)
    end
```

- [ ] **Step 2: Update refresh_all controller action**

Replace the `refresh_all` method in `app/controllers/completion_kit/provider_credentials_controller.rb`:

```ruby
    def refresh_all
      ProviderCredential.find_each do |cred|
        next unless %w[openai anthropic].include?(cred.provider)
        ModelDiscoveryService.new(config: cred.config_hash).refresh!
      end

      respond_to do |format|
        format.json do
          render json: {
            models_discovered: Model.count,
            for_generation: Model.for_generation.count,
            for_judging: Model.for_judging.count,
            generation_options_html: helpers.ck_model_options_html(:generation),
            judging_options_html: helpers.ck_model_options_html(:judging)
          }
        end
        format.html do
          redirect_back fallback_location: provider_credentials_path, notice: "Models refreshed."
        end
      end
    end
```

- [ ] **Step 3: Write test for JSON response**

In `spec/requests/completion_kit/provider_credentials_spec.rb`, add:

```ruby
  it "refresh_all returns JSON with model counts when requested" do
    create(:completion_kit_provider_credential, provider: "openai", api_key: "sk-test")
    create(:completion_kit_model, provider: "openai", model_id: "gpt-test", supports_generation: true, supports_judging: true)

    post "/completion_kit/refresh_models", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)
    expect(data).to include("models_discovered", "for_generation", "for_judging", "generation_options_html", "judging_options_html")
  end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec spec/`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/provider_credentials_controller.rb app/helpers/completion_kit/application_helper.rb spec/requests/completion_kit/provider_credentials_spec.rb
git commit -m "make refresh_all iterate all providers and return JSON with model counts"
```

---

### Task 3: Modal CSS and markup

**Files:**
- Modify: `app/assets/stylesheets/completion_kit/application.css`
- Modify: `app/views/layouts/completion_kit/application.html.erb`

- [ ] **Step 1: Add modal CSS**

Add to the end of `app/assets/stylesheets/completion_kit/application.css`:

```css
.ck-modal-overlay {
  display: none;
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  z-index: 1000;
  align-items: center;
  justify-content: center;
}

.ck-modal-overlay--visible {
  display: flex;
}

.ck-modal {
  background: var(--ck-surface);
  border: 1px solid var(--ck-line);
  border-radius: var(--ck-radius);
  padding: 2rem 2.5rem;
  text-align: center;
  min-width: 320px;
  max-width: 420px;
}

.ck-modal__spinner {
  display: inline-block;
  width: 24px;
  height: 24px;
  border: 3px solid var(--ck-line);
  border-top-color: var(--ck-accent);
  border-radius: 50%;
  animation: ck-spin 0.8s linear infinite;
  margin-bottom: 1rem;
}

@keyframes ck-spin {
  to { transform: rotate(360deg); }
}

.ck-modal__message {
  font-size: 0.9rem;
  color: var(--ck-muted);
  margin: 0;
}
```

- [ ] **Step 2: Add modal markup and shared JS to layout**

In `app/views/layouts/completion_kit/application.html.erb`, add before the closing `</body>` tag (before the existing `<script>` block):

```erb
<div class="ck-modal-overlay" id="ck-refresh-modal">
  <div class="ck-modal">
    <div class="ck-modal__spinner" id="ck-refresh-spinner"></div>
    <p class="ck-modal__message" id="ck-refresh-message">Discovering and probing models...</p>
  </div>
</div>
```

Then in the existing `<script>` block (or add a new one), add the `ckRefreshModels` function:

```javascript
function ckRefreshModels(selectId, scope) {
  if (!confirm("This will discover and probe models from all configured providers. This may take several minutes. Continue?")) return;

  var modal = document.getElementById("ck-refresh-modal");
  var spinner = document.getElementById("ck-refresh-spinner");
  var message = document.getElementById("ck-refresh-message");
  modal.classList.add("ck-modal-overlay--visible");
  spinner.style.display = "inline-block";
  message.textContent = "Discovering and probing models...";

  var csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute("content");

  fetch("/completion_kit/refresh_models", {
    method: "POST",
    headers: { "Accept": "application/json", "X-CSRF-Token": csrfToken }
  })
  .then(function(resp) { return resp.json(); })
  .then(function(data) {
    spinner.style.display = "none";
    message.textContent = "Done — " + data.models_discovered + " models discovered, " + data.for_generation + " for generation, " + data.for_judging + " for judging.";

    var select = document.getElementById(selectId);
    if (select) {
      var key = scope === "judging" ? "judging_options_html" : "generation_options_html";
      select.innerHTML = data[key];
    }

    setTimeout(function() { modal.classList.remove("ck-modal-overlay--visible"); }, 2500);
  })
  .catch(function(err) {
    spinner.style.display = "none";
    message.textContent = "Error: " + err.message;
    modal.addEventListener("click", function() { modal.classList.remove("ck-modal-overlay--visible"); }, { once: true });
  });
}
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/`

Expected: all pass (no functional changes to test, just markup/css/js).

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/completion_kit/application.css app/views/layouts/completion_kit/application.html.erb
git commit -m "add modal overlay markup, CSS, and ckRefreshModels JS function"
```

---

### Task 4: Wire refresh buttons to use modal

**Files:**
- Modify: `app/views/completion_kit/prompts/_form.html.erb`
- Modify: `app/views/completion_kit/runs/_form.html.erb`

- [ ] **Step 1: Update prompt form refresh button**

In `app/views/completion_kit/prompts/_form.html.erb`, replace the `ck-select-with-action` div (lines 34-37):

```erb
        <div class="ck-select-with-action">
          <%= form.select :llm_model, ck_grouped_models(available, prompt.llm_model), {}, { class: "ck-input", id: "prompt_llm_model" } %>
          <button type="button" class="ck-icon-btn" title="Refresh models" onclick="ckRefreshModels('prompt_llm_model','generation')"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path fill-rule="evenodd" d="M13.836 2.477a.75.75 0 0 1 .75.75v3.182a.75.75 0 0 1-.75.75h-3.182a.75.75 0 0 1 0-1.5h1.37l-.84-.841a4.5 4.5 0 0 0-7.08.681.75.75 0 0 1-1.264-.808 6 6 0 0 1 9.44-.908l.84.84V3.227a.75.75 0 0 1 .75-.75Zm-.911 7.5A.75.75 0 0 1 13.199 11a6 6 0 0 1-9.44.908l-.84-.84v1.68a.75.75 0 0 1-1.5 0V9.567a.75.75 0 0 1 .75-.75h3.182a.75.75 0 0 1 0 1.5h-1.37l.84.841a4.5 4.5 0 0 0 7.08-.681.75.75 0 0 1 1.024-.274Z" clip-rule="evenodd"/></svg></button>
        </div>
```

Key change: `button_to` (form submit) → plain `<button type="button">` with `onclick="ckRefreshModels(...)"`. The select needs an explicit `id: "prompt_llm_model"` so JS can find it.

- [ ] **Step 2: Update run form refresh button**

In `app/views/completion_kit/runs/_form.html.erb`, replace the `ck-select-with-action` div (lines 37-40):

```erb
        <div class="ck-select-with-action">
          <%= form.select :judge_model, ck_grouped_models(available, run.judge_model), { include_blank: "None" }, { class: "ck-input", id: "run_judge_model" } %>
          <button type="button" class="ck-icon-btn" title="Refresh models" onclick="ckRefreshModels('run_judge_model','judging')"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" width="16" height="16"><path fill-rule="evenodd" d="M13.836 2.477a.75.75 0 0 1 .75.75v3.182a.75.75 0 0 1-.75.75h-3.182a.75.75 0 0 1 0-1.5h1.37l-.84-.841a4.5 4.5 0 0 0-7.08.681.75.75 0 0 1-1.264-.808 6 6 0 0 1 9.44-.908l.84.84V3.227a.75.75 0 0 1 .75-.75Zm-.911 7.5A.75.75 0 0 1 13.199 11a6 6 0 0 1-9.44.908l-.84-.84v1.68a.75.75 0 0 1-1.5 0V9.567a.75.75 0 0 1 .75-.75h3.182a.75.75 0 0 1 0 1.5h-1.37l.84.841a4.5 4.5 0 0 0 7.08-.681.75.75 0 0 1 1.024-.274Z" clip-rule="evenodd"/></svg></button>
        </div>
```

- [ ] **Step 3: Run full test suite**

Run: `bundle exec rspec spec/`

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add app/views/completion_kit/prompts/_form.html.erb app/views/completion_kit/runs/_form.html.erb
git commit -m "wire refresh buttons to use confirm dialog and loading modal"
```

---

### Task 5: End-to-end verification

**Files:** None new.

- [ ] **Step 1: Run full test suite**

Run: `bundle exec rspec spec/`

Expected: all pass, 100% coverage.

- [ ] **Step 2: Test in browser**

1. Navigate to prompt edit form
2. Click the refresh icon next to the model dropdown
3. Confirm dialog should appear
4. Click OK — modal with spinner should appear
5. Wait for completion — modal should show "Done — X models discovered..."
6. Dropdown should update with new models
7. Modal should auto-close after 2.5 seconds

Repeat on the run form for the judge model dropdown.

- [ ] **Step 3: Commit any fixes**
