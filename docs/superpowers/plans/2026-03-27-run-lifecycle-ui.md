# Run Lifecycle UI Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the run show page update fully via Turbo broadcasts so the status header, progress area, error display, and action buttons all stay in sync throughout the run lifecycle.

**Architecture:** Extract the status header, progress/error area, and action buttons into broadcast-targetable partials. Add new broadcast methods to the Run model that replace these targets on every state change. Remove the server-rendered error flash and the redundant "Generation started" flash notice.

**Tech Stack:** Rails 7 Turbo Streams, ERB partials, RSpec

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `app/views/completion_kit/runs/_status_header.html.erb` | Create | Status dot + status text + run name + prompt link (the `ck-page-header` section) |
| `app/views/completion_kit/runs/_actions.html.erb` | Create | Action buttons (Delete, Edit, Re-judge, Start) |
| `app/views/completion_kit/runs/_progress.html.erb` | Modify | Add completed state, add failed state with error message, add `generating`/`judging` states (already there) |
| `app/views/completion_kit/runs/show.html.erb` | Modify | Replace inline header/actions/error with partials wrapped in Turbo target divs |
| `app/models/completion_kit/run.rb` | Modify | Add `broadcast_status_header` and `broadcast_actions` methods; call them alongside `broadcast_progress` |
| `app/controllers/completion_kit/runs_controller.rb` | Modify | Remove flash notice from `generate` and `judge` actions |
| `spec/models/completion_kit/run_spec.rb` | Modify | Add tests for new broadcast methods |

---

### Task 1: Extract `_status_header` partial

**Files:**
- Create: `app/views/completion_kit/runs/_status_header.html.erb`
- Modify: `app/views/completion_kit/runs/show.html.erb`

- [ ] **Step 1: Create the `_status_header` partial**

Create `app/views/completion_kit/runs/_status_header.html.erb`:

```erb
<div id="run_status_header">
  <section class="ck-page-header">
    <div>
      <p class="ck-kicker"><span class="<%= ck_run_dot(run) %>"></span> <%= run.status.capitalize %></p>
      <h1 class="ck-title"><%= run.name %></h1>
      <p class="ck-meta-copy"><%= link_to run.prompt.display_name, prompt_path(run.prompt), class: "ck-link" %>&ensp;<span class="ck-chip" style="text-transform: none;"><%= run.prompt.llm_model %></span></p>
    </div>
    <%= render "actions", run: run %>
  </section>
</div>
```

- [ ] **Step 2: Update `show.html.erb` to use the partial**

Replace the `<section class="ck-page-header">...</section>` block (lines 8–24) with:

```erb
<%= render "status_header", run: @run %>
```

- [ ] **Step 3: Verify the page renders identically**

Run: `bundle exec rspec spec/requests/` or load the page in browser. The HTML output should be identical (wrapped in a `<div id="run_status_header">`).

- [ ] **Step 4: Commit**

```
git add app/views/completion_kit/runs/_status_header.html.erb app/views/completion_kit/runs/show.html.erb
git commit -m "extract _status_header partial from run show page"
```

---

### Task 2: Extract `_actions` partial

**Files:**
- Create: `app/views/completion_kit/runs/_actions.html.erb`
- Modify: `app/views/completion_kit/runs/_status_header.html.erb` (already references it)

- [ ] **Step 1: Create the `_actions` partial**

Create `app/views/completion_kit/runs/_actions.html.erb`:

```erb
<div class="ck-actions" id="run_actions">
  <%= button_to run_path(run), method: :delete, form_class: "inline-block", class: "ck-icon-btn", title: "Delete run", data: { turbo_confirm: "Delete this run and all its responses?" } do %><%= heroicon_tag "trash", variant: :outline, size: 16 %><% end %>
  <%= link_to "Edit", edit_run_path(run), class: ck_button_classes(:light, variant: :outline) %>
  <% if run.judge_configured? && run.status == "completed" %>
    <%= button_to "Re-judge", judge_run_path(run), method: :post, class: ck_button_classes(:light, variant: :outline), form_class: "inline-block" %>
  <% end %>
  <% if run.status == "pending" || (run.status == "completed" && run.responses.empty?) || run.status == "failed" %>
    <%= button_to "Start", generate_run_path(run), method: :post, class: ck_button_classes(:dark), form_class: "inline-block" %>
  <% end %>
</div>
```

- [ ] **Step 2: Verify the `_status_header` partial already renders `_actions`**

The `_status_header` partial created in Task 1 already contains `<%= render "actions", run: run %>`. Confirm the old `<div class="ck-actions">` block is no longer in `show.html.erb` or `_status_header.html.erb` inline — it should only live in `_actions.html.erb`.

- [ ] **Step 3: Verify the page renders correctly**

Load the page in browser or run request specs. Buttons should appear exactly as before.

- [ ] **Step 4: Commit**

```
git add app/views/completion_kit/runs/_actions.html.erb app/views/completion_kit/runs/_status_header.html.erb
git commit -m "extract _actions partial from run show page"
```

---

### Task 3: Expand `_progress` partial to handle completed and failed states

**Files:**
- Modify: `app/views/completion_kit/runs/_progress.html.erb`
- Modify: `app/views/completion_kit/runs/show.html.erb` (remove inline error flash)

- [ ] **Step 1: Rewrite `_progress.html.erb`**

Replace the entire contents of `app/views/completion_kit/runs/_progress.html.erb` with:

```erb
<div id="run_progress">
  <% if run.status == "generating" || run.status == "judging" %>
    <div style="margin: 1.5rem 0;">
      <div class="ck-split" style="margin-bottom: 0.35rem;">
        <p class="ck-kicker"><%= run.status == "generating" ? "Generating responses..." : "Judging responses..." %></p>
        <p class="ck-meta-copy" style="font-size: 0.8rem;"><%= run.progress_current %> / <%= run.progress_total %></p>
      </div>
      <div style="background: var(--ck-surface-soft); border-radius: 4px; overflow: hidden; height: 4px;">
        <% pct = run.progress_total > 0 ? (run.progress_current.to_f / run.progress_total * 100).round : 0 %>
        <div style="width: <%= pct %>%; height: 100%; background: var(--ck-accent); transition: width 0.3s;"></div>
      </div>
    </div>
  <% elsif run.status == "failed" %>
    <div class="ck-flash ck-flash--alert" style="margin-top: 1rem;">
      <% error_resp = run.responses.where("response_text LIKE 'Error:%'").last %>
      <%= error_resp&.response_text || "Run failed. Check your provider configuration and try again." %>
    </div>
  <% elsif run.status == "completed" && run.progress_total.to_i > 0 %>
    <div style="margin: 1.5rem 0;">
      <div class="ck-split" style="margin-bottom: 0.35rem;">
        <p class="ck-kicker">Completed</p>
        <p class="ck-meta-copy" style="font-size: 0.8rem;"><%= run.progress_total %> / <%= run.progress_total %></p>
      </div>
      <div style="background: var(--ck-surface-soft); border-radius: 4px; overflow: hidden; height: 4px;">
        <div style="width: 100%; height: 100%; background: var(--ck-success, #22c55e); transition: width 0.3s;"></div>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Remove inline error flash from `show.html.erb`**

Delete lines 61–66 from `show.html.erb` (the `<% if @run.status == "failed" %>` block with `ck-flash--alert`). The `_progress` partial now handles this.

- [ ] **Step 3: Verify states render correctly**

Load runs in each status in the browser, or inspect the partial rendering with different run statuses. The progress partial should now show:
- `pending`: nothing
- `generating`/`judging`: progress bar (unchanged)
- `completed`: green completed bar
- `failed`: error flash message

- [ ] **Step 4: Commit**

```
git add app/views/completion_kit/runs/_progress.html.erb app/views/completion_kit/runs/show.html.erb
git commit -m "expand _progress partial to show completed and failed states"
```

---

### Task 4: Add broadcast methods for status header and actions

**Files:**
- Modify: `app/models/completion_kit/run.rb`
- Test: `spec/models/completion_kit/run_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/completion_kit/run_spec.rb` inside the `"broadcast helpers"` describe block:

```ruby
it "broadcast_status_header calls broadcast_replace_to with run_status_header target" do
  run.send(:broadcast_status_header)
  expect(run).to have_received(:broadcast_replace_to).with(
    "completion_kit_run_#{run.id}",
    hash_including(target: "run_status_header")
  )
end

it "broadcast_actions calls broadcast_replace_to with run_actions target" do
  run.send(:broadcast_actions)
  expect(run).to have_received(:broadcast_replace_to).with(
    "completion_kit_run_#{run.id}",
    hash_including(target: "run_actions")
  )
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -v`

Expected: 2 failures — `NoMethodError: undefined method 'broadcast_status_header'` and `'broadcast_actions'`.

- [ ] **Step 3: Implement the broadcast methods**

Add to the `private` section of `app/models/completion_kit/run.rb`, after the existing `broadcast_progress` method:

```ruby
def broadcast_status_header
  broadcast_replace_to(
    "completion_kit_run_#{id}",
    target: "run_status_header",
    partial: "completion_kit/runs/status_header",
    locals: { run: self }
  )
end

def broadcast_actions
  broadcast_replace_to(
    "completion_kit_run_#{id}",
    target: "run_actions",
    partial: "completion_kit/runs/actions",
    locals: { run: self }
  )
end
```

- [ ] **Step 4: Update the global stub in the spec `before` block**

In `spec/models/completion_kit/run_spec.rb`, update the top-level `before` block (lines 6–9) to also stub the new methods:

```ruby
before do
  allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_progress)
  allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response)
  allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_response_update)
  allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_status_header)
  allow_any_instance_of(CompletionKit::Run).to receive(:broadcast_actions)
end
```

And in the `"broadcast helpers"` describe block, update the inner `before` to also call original and stub for these:

```ruby
before do
  allow(run).to receive(:broadcast_progress).and_call_original
  allow(run).to receive(:broadcast_response).and_call_original
  allow(run).to receive(:broadcast_response_update).and_call_original
  allow(run).to receive(:broadcast_status_header).and_call_original
  allow(run).to receive(:broadcast_actions).and_call_original
  allow(run).to receive(:broadcast_replace_to)
  allow(run).to receive(:broadcast_append_to)
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -v`

Expected: all pass.

- [ ] **Step 6: Commit**

```
git add app/models/completion_kit/run.rb spec/models/completion_kit/run_spec.rb
git commit -m "add broadcast_status_header and broadcast_actions methods to Run"
```

---

### Task 5: Wire broadcast calls into the run lifecycle

**Files:**
- Modify: `app/models/completion_kit/run.rb`

This task adds `broadcast_status_header` and `broadcast_actions` calls at every state transition point. The calls go alongside the existing `broadcast_progress` calls.

- [ ] **Step 1: Create a helper to broadcast all UI targets**

Add a private method in `app/models/completion_kit/run.rb`:

```ruby
def broadcast_ui
  broadcast_progress
  broadcast_status_header
  broadcast_actions
end
```

- [ ] **Step 2: Replace `broadcast_progress` calls with `broadcast_ui`**

In `generate_responses!`, replace every `broadcast_progress` call with `broadcast_ui`:

1. After `update!(status: "generating", ...)` — line 61: change `broadcast_progress` to `broadcast_ui`
2. After `update_columns(progress_current: index + 1)` — line 75: keep as `broadcast_progress` (only the progress bar changes mid-generation, not header/actions)
3. After `update!(status: "completed")` — line 83: change `broadcast_progress` to `broadcast_ui`
4. In the `rescue Faraday::Error` block — line 90: change `broadcast_progress` to `broadcast_ui`
5. In the `rescue StandardError` block — line 95: change `broadcast_progress if persisted?` to `broadcast_ui if persisted?`

In `judge_responses!`, same pattern:

1. After `update!(status: "judging", ...)` — line 102: change `broadcast_progress` to `broadcast_ui`
2. After `update_columns(progress_current: evaluation_count)` — line 131: keep as `broadcast_progress`
3. After `update!(status: "completed")` — line 137: change `broadcast_progress` to `broadcast_ui`
4. In the `rescue Faraday::Error` block — line 142: change `broadcast_progress` to `broadcast_ui`
5. In the `rescue StandardError` block — line 147: change `broadcast_progress if persisted?` to `broadcast_ui if persisted?`

The full updated `generate_responses!` method:

```ruby
def generate_responses!
  rows = if dataset
           CsvProcessor.process_self(self)
         else
           [{}]
         end

  if rows.empty?
    errors.add(:base, "Dataset has no rows")
    return false
  end

  client = LlmClient.for_model(prompt.llm_model, ApiConfig.for_model(prompt.llm_model))

  unless client.configured?
    errors.add(:base, "LLM API not configured: #{client.configuration_errors.join(', ')}")
    update_column(:status, "failed") if persisted?
    return false
  end

  update!(status: "generating", progress_current: 0, progress_total: rows.length)
  responses.destroy_all
  broadcast_ui

  rows.each_with_index do |row, index|
    input = row.empty? ? nil : row.to_json
    rendered = CsvProcessor.apply_variables(prompt, row)
    response_text = client.generate_completion(rendered, model: prompt.llm_model)

    resp = responses.create!(
      input_data: input,
      response_text: response_text,
      expected_output: row["expected_output"]
    )

    update_columns(progress_current: index + 1)
    broadcast_progress
    broadcast_response(resp)
  end

  if judge_configured?
    judge_responses!
  else
    update!(status: "completed")
    broadcast_ui
  end

  true
rescue Faraday::Error => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_ui
  false
rescue StandardError => e
  update_columns(status: "failed") if persisted?
  errors.add(:base, e.message)
  broadcast_ui if persisted?
  false
end
```

The full updated `judge_responses!` method:

```ruby
def judge_responses!
  total_evaluations = responses.count * metrics.count
  update!(status: "judging", progress_current: 0, progress_total: total_evaluations)
  broadcast_ui

  judge = JudgeService.new(ApiConfig.for_model(judge_model).merge(judge_model: judge_model))
  evaluation_count = 0

  responses.find_each do |response|
    metrics.each do |metric|
      evaluation = judge.evaluate(
        response.response_text,
        response.expected_output,
        prompt.template,
        criteria: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
        evaluation_steps: metric.respond_to?(:evaluation_steps) ? metric.evaluation_steps : nil,
        rubric_text: metric.respond_to?(:display_rubric_text) ? metric.display_rubric_text : nil
      )

      response.reviews.find_or_initialize_by(metric_id: metric.id).tap do |review|
        review.assign_attributes(
          metric_name: metric.name,
          instruction: metric.respond_to?(:instruction) ? metric.instruction.to_s : "",
          status: "evaluated",
          ai_score: evaluation[:score],
          ai_feedback: evaluation[:feedback]
        )
        review.save!
      end

      evaluation_count += 1
      update_columns(progress_current: evaluation_count)
      broadcast_progress
    end

    broadcast_response_update(response)
  end

  update!(status: "completed")
  broadcast_ui
  true
rescue Faraday::Error => e
  update_columns(status: "failed")
  errors.add(:base, e.message)
  broadcast_ui
  false
rescue StandardError => e
  update_columns(status: "failed") if persisted?
  errors.add(:base, e.message)
  broadcast_ui if persisted?
  false
end
```

- [ ] **Step 3: Run the full test suite**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -v`

Expected: all pass. The stubs from Task 4 cover the new `broadcast_status_header` and `broadcast_actions` calls.

- [ ] **Step 4: Commit**

```
git add app/models/completion_kit/run.rb
git commit -m "broadcast status header and actions on every run state transition"
```

---

### Task 6: Remove redundant flash notices from controller

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb`

- [ ] **Step 1: Remove flash notice from `generate` action**

Change the `generate` method from:

```ruby
def generate
  GenerateJob.perform_later(@run.id)
  redirect_to run_path(@run), notice: "Generation started."
end
```

To:

```ruby
def generate
  GenerateJob.perform_later(@run.id)
  redirect_to run_path(@run)
end
```

- [ ] **Step 2: Remove flash notice from `judge` action**

Change the `judge` method from:

```ruby
def judge
  if params[:run]
    @run.update(judge_model: params[:run][:judge_model])
  end
  JudgeJob.perform_later(@run.id)
  redirect_to run_path(@run), notice: "Judging started."
end
```

To:

```ruby
def judge
  if params[:run]
    @run.update(judge_model: params[:run][:judge_model])
  end
  JudgeJob.perform_later(@run.id)
  redirect_to run_path(@run)
end
```

- [ ] **Step 3: Run request specs if they exist**

Run: `bundle exec rspec spec/requests/ -v` or `bundle exec rspec spec/controllers/ -v`

If any tests assert the flash notice text, update them to not expect a notice.

- [ ] **Step 4: Commit**

```
git add app/controllers/completion_kit/runs_controller.rb
git commit -m "remove redundant flash notices from generate and judge actions"
```

---

### Task 7: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bundle exec rake spec`

Expected: all tests pass, including coverage requirements.

- [ ] **Step 2: Manual verification**

Load the run show page in a browser and verify each state visually:

1. **Pending run**: Status shows "Pending" with pulsing dot, Start button visible, no progress bar
2. **Click Start**: Page redirects, no flash notice. Within seconds the progress bar appears, status updates to "Generating", Start button disappears
3. **Mid-generation**: Progress bar fills, responses appear in list
4. **If judge configured**: Status changes to "Judging", progress bar resets, Re-judge button hidden
5. **Completion**: Status changes to "Completed" with green dot, green completed bar shown, Re-judge button appears (if judge configured)
6. **Failure** (test by misconfiguring API key): Status changes to "Failed" with red dot, error message appears in the progress area, Start button reappears for retry

- [ ] **Step 3: Commit any fixes found during manual testing**
