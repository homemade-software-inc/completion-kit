# Run-Retention Display Seams Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a multi-tenant host one unified seam to apply run-history retention across every place the engine lists, counts, or traverses runs — not just the runs index.

**Architecture:** Replace the two 0.16.3 hooks (`runs_index_scope`, `runs_index_footer_partial`) with a single `config.runs_display_scope` plus a renamed `config.runs_display_footer_partial`. Two model primitives carry the scope everywhere: `Run.display_scoped` (a class method that applies the configured callable to the current relation) for run **list/count** sites, and `Run.visible_run_ids` (a subquery relation) for **child-record** queries (agreements, responses) via `where(run_id: Run.visible_run_ids)`. The judge few-shot seeding path stays unfiltered.

**Tech Stack:** Rails engine, RSpec + FactoryBot, SimpleCov (100% line + branch enforced).

## Global Constraints

- Namespace all code under `CompletionKit`. (CLAUDE.md)
- No code comments anywhere. (user rule — docs go in README, not inline)
- No em dashes, no italics in any copy. (user rule)
- 100% line AND branch coverage; CI enforces it. Run `bundle exec rspec` from the engine root.
- This **replaces** `runs_index_scope` / `runs_index_footer_partial` shipped in 0.16.3. It is a breaking rename; record it under CHANGELOG `### Changed`.
- `runs_display_scope` callable contract: zero-arg, `instance_exec`'d against a `Run` relation (`self` is the relation), MUST return a relation. Same style as `tenant_scope`.
- Apply the scope but NEVER to: delete-confirm cascade counts (`prompts/_form.html.erb`, `datasets/_form.html.erb`), id-addressed single lookups (`runs#show`, `runs_get`, API `show`), `MetricAgreementExamples.judge_examples_for` (few-shot seeding — valid on hidden runs), and `Run` auto-name counters (`run.rb` `set_auto_name`).
- Dashboard (`DashboardController`, `DashboardStats`) is OUT OF SCOPE: shipped host-side (Wave 1) and aggregates are a separate issue.

---

### Task 1: Config — replace the 0.16.3 hooks

**Files:**
- Modify: `lib/completion_kit.rb:13`
- Test: `spec/lib/completion_kit_config_spec.rb` (create if absent; otherwise add to the nearest config spec)

**Interfaces:**
- Produces: `CompletionKit.config.runs_display_scope` (callable or nil), `CompletionKit.config.runs_display_footer_partial` (String or nil). Both default nil.

- [ ] **Step 1: Write the failing test**

```ruby
require "rails_helper"

RSpec.describe CompletionKit::Configuration do
  it "defaults the run-display seams to nil and no longer exposes the 0.16.3 names" do
    config = described_class.new
    expect(config.runs_display_scope).to be_nil
    expect(config.runs_display_footer_partial).to be_nil
    expect(config).not_to respond_to(:runs_index_scope)
    expect(config).not_to respond_to(:runs_index_footer_partial)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/completion_kit_config_spec.rb`
Expected: FAIL — `runs_index_scope` still responds / `runs_display_scope` undefined.

- [ ] **Step 3: Implement**

In `lib/completion_kit.rb` replace line 13:

```ruby
    attr_accessor :runs_display_scope, :runs_display_footer_partial
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/lib/completion_kit_config_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/completion_kit.rb spec/lib/completion_kit_config_spec.rb
git commit -m "Replace runs_index_* config with unified runs_display_* seams"
```

---

### Task 2: `Run.display_scoped` + `Run.visible_run_ids` primitives

**Files:**
- Modify: `app/models/completion_kit/run.rb` (add class methods after the validations block, ~line 22)
- Test: `spec/models/completion_kit/run_spec.rb` (add a `describe ".display_scoped"` block)

**Interfaces:**
- Produces:
  - `Run.display_scoped` → relation. With no config, returns `all` unchanged. With config, returns `all.instance_exec(&callable)`. Chainable onto any Run relation (`Run.where(...).display_scoped`, `dataset.runs.display_scoped`).
  - `Run.visible_run_ids` → `display_scoped.select(:id)` (subquery relation) for `where(run_id: Run.visible_run_ids)`.

- [ ] **Step 1: Write the failing test**

```ruby
  describe ".display_scoped" do
    it "returns all runs when no runs_display_scope is configured" do
      recent = create(:completion_kit_run)
      old = create(:completion_kit_run, created_at: 90.days.ago)
      expect(CompletionKit::Run.display_scoped).to match_array([recent, old])
    end

    it "applies the configured callable to the current relation" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.display_scoped).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "exposes visible_run_ids as a subquery usable by child records" do
      recent = create(:completion_kit_run)
      create(:completion_kit_run, created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(CompletionKit::Run.where(id: CompletionKit::Run.visible_run_ids)).to eq([recent])
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -e display_scoped`
Expected: FAIL — `NoMethodError: display_scoped`.

- [ ] **Step 3: Implement**

In `app/models/completion_kit/run.rb`, after the `before_validation` lines (~line 22):

```ruby
    def self.display_scoped
      filter = CompletionKit.config.runs_display_scope
      filter ? all.instance_exec(&filter) : all
    end

    def self.visible_run_ids
      display_scoped.select(:id)
    end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/completion_kit/run_spec.rb -e display_scoped`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/run.rb spec/models/completion_kit/run_spec.rb
git commit -m "Add Run.display_scoped and Run.visible_run_ids retention primitives"
```

---

### Task 3: Migrate RunsController#index + footer helper

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb:7-12`
- Modify: `app/helpers/completion_kit/application_helper.rb` (add `ck_runs_display_footer`)
- Modify: `app/views/completion_kit/runs/index.html.erb:26-28`
- Modify: `spec/requests/completion_kit/runs_spec.rb` (rename the two existing seam specs)

**Interfaces:**
- Consumes: `Run.display_scoped` (Task 2).
- Produces: `ck_runs_display_footer(runs)` helper — renders `config.runs_display_footer_partial` with `runs:` local, or nothing when unset.

- [ ] **Step 1: Rewrite the two existing seam specs in `spec/requests/completion_kit/runs_spec.rb`**

Replace the `runs_index_scope` filtering spec and the footer spec (the two added in 0.16.3) with:

```ruby
  it "filters the index list through a host-configured runs_display_scope" do
    create(:completion_kit_run, prompt: prompt, name: "Recent Run")
    create(:completion_kit_run, prompt: prompt, name: "Old Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get base_path

    expect(response.body).to include("Recent Run")
    expect(response.body).not_to include("Old Run")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "passes the shown (post-scope) runs to the host-configured runs_display_footer_partial as a local" do
    create(:completion_kit_run, prompt: prompt, name: "Recent A")
    create(:completion_kit_run, prompt: prompt, name: "Recent B")
    create(:completion_kit_run, prompt: prompt, name: "Old Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
    CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

    get base_path

    expect(response.body).to include("spec-host-runs-footer: 2 runs in view")
  ensure
    CompletionKit.config.runs_display_footer_partial = nil
    CompletionKit.config.runs_display_scope = nil
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/runs_spec.rb -e runs_display`
Expected: FAIL — config setters undefined / footer not rendered with the local.

- [ ] **Step 3: Implement controller + helper + view**

`app/controllers/completion_kit/runs_controller.rb` index (replace lines 7-12):

```ruby
    def index
      scope = Run.includes(:prompt, :dataset, :tags, responses: :reviews).order(created_at: :desc).display_scoped
      @runs = apply_tag_filter(scope)
    end
```

`app/helpers/completion_kit/application_helper.rb` (add inside the module):

```ruby
    def ck_runs_display_footer(runs)
      partial = CompletionKit.config.runs_display_footer_partial
      return unless partial
      render partial, runs: runs
    end
```

`app/views/completion_kit/runs/index.html.erb` (replace lines 26-28):

```erb
<%= ck_runs_display_footer(@runs) %>
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/runs_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/runs_controller.rb app/helpers/completion_kit/application_helper.rb app/views/completion_kit/runs/index.html.erb spec/requests/completion_kit/runs_spec.rb
git commit -m "Migrate runs index + footer to unified runs_display seams"
```

---

### Task 4: RunsController#compare and #new

**Files:**
- Modify: `app/controllers/completion_kit/runs_controller.rb:87-90` (compare `@other_runs`) and `:36` (new `last_run`)
- Test: `spec/requests/completion_kit/runs_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`.

- [ ] **Step 1: Write the failing tests**

```ruby
  it "excludes runs hidden by runs_display_scope from the compare picker" do
    dataset = create(:completion_kit_dataset)
    anchor = create(:completion_kit_run, prompt: prompt, dataset: dataset, status: "completed")
    create(:completion_kit_run, prompt: prompt, dataset: dataset, name: "Old Candidate", created_at: 90.days.ago, status: "completed")
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "#{base_path}/#{anchor.id}/compare"

    expect(response.body).not_to include("Old Candidate")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end

  it "does not seed new-run tags from a run hidden by runs_display_scope" do
    create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago, tag_names: ["stale"])
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "#{base_path}/new", params: { prompt_id: prompt.id }

    expect(response.body).not_to match(/value="stale"[^>]*\bchecked\b/)
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/runs_spec.rb -e runs_display_scope`
Expected: FAIL — old candidate present / stale tag checked.

- [ ] **Step 3: Implement**

`compare` (line 87-90) — insert `.display_scoped` before `.order`:

```ruby
        @other_runs = Run.where(dataset_id: @run.dataset_id, prompt_id: @run.prompt_id)
                          .where.not(id: @run.id)
                          .display_scoped
                          .order(created_at: :desc)
                          .limit(50)
```

`new` (line 36) — insert `.display_scoped`:

```ruby
        last_run = Run.where(prompt_id: prompt.family_versions.ids).display_scoped.order(created_at: :desc).first
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/runs_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/runs_controller.rb spec/requests/completion_kit/runs_spec.rb
git commit -m "Apply runs_display_scope to run compare picker and new-run tag defaults"
```

---

### Task 5: PromptsController#show + footer slot

**Files:**
- Modify: `app/controllers/completion_kit/prompts_controller.rb:11-13`
- Modify: `app/views/completion_kit/prompts/show.html.erb` (after the runs section, ~line 144)
- Test: `spec/requests/completion_kit/prompts_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`, `ck_runs_display_footer`.

- [ ] **Step 1: Write the failing test**

```ruby
  it "scopes the prompt's run list and renders the display footer with shown runs" do
    create(:completion_kit_run, prompt: prompt, name: "Recent Prompt Run")
    create(:completion_kit_run, prompt: prompt, name: "Old Prompt Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
    CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

    get "/completion_kit/prompts/#{prompt.id}"

    expect(response.body).to include("Recent Prompt Run")
    expect(response.body).not_to include("Old Prompt Run")
    expect(response.body).to include("spec-host-runs-footer: 1 runs in view")
  ensure
    CompletionKit.config.runs_display_footer_partial = nil
    CompletionKit.config.runs_display_scope = nil
  end
```

(If `prompt` is not already a `let` in this spec, add `let!(:prompt) { create(:completion_kit_prompt, name: "Prompt A") }`.)

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb -e "display footer"`
Expected: FAIL — old run present, footer absent.

- [ ] **Step 3: Implement**

`prompts_controller.rb` show (lines 11-13):

```ruby
      @runs = Run.where(prompt_id: @prompt.family_versions.select(:id))
                 .includes(:prompt, :dataset, responses: :reviews)
                 .order(created_at: :desc)
                 .display_scoped
```

`prompts/show.html.erb` — after the `<% end %>` that closes the `<% if @runs.any? %>` runs section (~line 144), add:

```erb
<%= ck_runs_display_footer(@runs) %>
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/prompts_controller.rb app/views/completion_kit/prompts/show.html.erb spec/requests/completion_kit/prompts_spec.rb
git commit -m "Scope prompt show run list and add display footer slot"
```

---

### Task 6: DatasetsController#show + footer slot

**Files:**
- Modify: `app/controllers/completion_kit/datasets_controller.rb:11`
- Modify: `app/views/completion_kit/datasets/show.html.erb` (after the runs section, ~line 73)
- Test: `spec/requests/completion_kit/datasets_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`, `ck_runs_display_footer`.

- [ ] **Step 1: Write the failing test**

```ruby
  it "scopes the dataset's run list and renders the display footer with shown runs" do
    dataset = create(:completion_kit_dataset)
    create(:completion_kit_run, dataset: dataset, name: "Recent DS Run")
    create(:completion_kit_run, dataset: dataset, name: "Old DS Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }
    CompletionKit.config.runs_display_footer_partial = "spec_host/runs_footer"

    get "/completion_kit/datasets/#{dataset.id}"

    expect(response.body).to include("Recent DS Run")
    expect(response.body).not_to include("Old DS Run")
    expect(response.body).to include("spec-host-runs-footer: 1 runs in view")
  ensure
    CompletionKit.config.runs_display_footer_partial = nil
    CompletionKit.config.runs_display_scope = nil
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/datasets_spec.rb -e "display footer"`
Expected: FAIL.

- [ ] **Step 3: Implement**

`datasets_controller.rb` show (line 11):

```ruby
      @runs = @dataset.runs.includes(:prompt, :responses).order(created_at: :desc).display_scoped
```

`datasets/show.html.erb` — after the `<% end %>` closing the runs section (~line 73):

```erb
<%= ck_runs_display_footer(@runs) %>
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/datasets_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/datasets_controller.rb app/views/completion_kit/datasets/show.html.erb spec/requests/completion_kit/datasets_spec.rb
git commit -m "Scope dataset show run list and add display footer slot"
```

---

### Task 7: Index page run-count cells

**Files:**
- Modify: `app/views/completion_kit/prompts/index.html.erb:54` (`family_runs`)
- Modify: `app/views/completion_kit/datasets/index.html.erb:39`
- Test: `spec/requests/completion_kit/prompts_spec.rb`, `spec/requests/completion_kit/datasets_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`.

- [ ] **Step 1: Write the failing tests**

prompts_spec:

```ruby
  it "counts only display-scoped runs in the prompt family count cell" do
    create(:completion_kit_run, prompt: prompt)
    create(:completion_kit_run, prompt: prompt, created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/prompts"

    expect(response.body).to match(/ck-prompts-table__runs-count">1</)
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

datasets_spec:

```ruby
  it "counts only display-scoped runs in the dataset used-in cell" do
    dataset = create(:completion_kit_dataset)
    create(:completion_kit_run, dataset: dataset)
    create(:completion_kit_run, dataset: dataset, created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/datasets"

    expect(response.body).to include('data-label="Used in">1<')
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb spec/requests/completion_kit/datasets_spec.rb -e "display-scoped runs"`
Expected: FAIL — count shows 2.

- [ ] **Step 3: Implement**

`prompts/index.html.erb` line 54:

```erb
          <% family_runs = CompletionKit::Run.where(prompt_id: prompt.family_versions.select(:id)).display_scoped %>
```

`datasets/index.html.erb` line 39:

```erb
          <td data-label="Used in"><%= dataset.runs.display_scoped.count %></td>
```

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rspec spec/requests/completion_kit/prompts_spec.rb spec/requests/completion_kit/datasets_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/views/completion_kit/prompts/index.html.erb app/views/completion_kit/datasets/index.html.erb spec/requests/completion_kit/prompts_spec.rb spec/requests/completion_kit/datasets_spec.rb
git commit -m "Scope index run-count cells to display-scoped runs"
```

---

### Task 8: API v1 runs index + X-Total-Count

**Files:**
- Modify: `app/controllers/completion_kit/api/v1/runs_controller.rb:8`
- Test: `spec/requests/completion_kit/api/v1/runs_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`. The scope must be applied BEFORE `paginate` (which counts before limit/offset) so `X-Total-Count` honors retention.

- [ ] **Step 1: Write the failing test**

```ruby
  it "excludes display-scoped-out runs from the list and the X-Total-Count header" do
    create(:completion_kit_run, name: "Recent API Run")
    create(:completion_kit_run, name: "Old API Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/api/v1/runs", headers: auth_headers

    body = JSON.parse(response.body)
    expect(body.map { |r| r["name"] }).to contain_exactly("Recent API Run")
    expect(response.headers["X-Total-Count"]).to eq("1")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

(Use whatever auth header helper this spec already defines; match the existing examples in the file.)

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/api/v1/runs_spec.rb -e "X-Total-Count"`
Expected: FAIL — count 2, old run present.

- [ ] **Step 3: Implement**

`api/v1/runs_controller.rb` line 8:

```ruby
          scope = Run.includes(:tags).display_scoped
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/api/v1/runs_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/api/v1/runs_controller.rb spec/requests/completion_kit/api/v1/runs_spec.rb
git commit -m "Honor runs_display_scope in API v1 runs index and X-Total-Count"
```

---

### Task 9: MCP runs_list tool

**Files:**
- Modify: `app/services/completion_kit/mcp_tools/runs.rb:60`
- Test: `spec/services/completion_kit/mcp_tools/runs_spec.rb` (or the existing MCP tools spec for runs)

**Interfaces:** Consumes `Run.display_scoped`. `runs_get` (line 64) stays unscoped (id-addressed).

- [ ] **Step 1: Write the failing test**

```ruby
  it "lists only display-scoped runs" do
    create(:completion_kit_run, name: "Recent MCP Run")
    create(:completion_kit_run, name: "Old MCP Run", created_at: 90.days.ago)
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    result = CompletionKit::McpTools::Runs.list({})
    names = JSON.parse(result[:content].first[:text]).map { |r| r["name"] }

    expect(names).to contain_exactly("Recent MCP Run")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

(Match the exact return shape `text_result` produces — inspect a neighboring test in the same file and mirror its parsing.)

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/runs_spec.rb -e "display-scoped"`
Expected: FAIL — both runs listed.

- [ ] **Step 3: Implement**

`mcp_tools/runs.rb` line 60:

```ruby
        text_result(Run.display_scoped.order(created_at: :desc).map(&:as_json))
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/services/completion_kit/mcp_tools/runs_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/mcp_tools/runs.rb spec/services/completion_kit/mcp_tools/runs_spec.rb
git commit -m "Scope MCP runs_list to display-scoped runs"
```

---

### Task 10: API reference recent-runs panel

**Files:**
- Modify: `app/controllers/completion_kit/api_reference_controller.rb:5`
- Test: `spec/requests/completion_kit/api_reference_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`.

- [ ] **Step 1: Write the failing test**

```ruby
  it "omits display-scoped-out runs from the recent-runs panel" do
    create(:completion_kit_prompt, name: "Doc Prompt").tap do |p|
      create(:completion_kit_run, prompt: p, name: "Recent Doc Run")
      create(:completion_kit_run, prompt: p, name: "Old Doc Run", created_at: 90.days.ago)
    end
    CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

    get "/completion_kit/api_reference"

    expect(response.body).to include("Recent Doc Run")
    expect(response.body).not_to include("Old Doc Run")
  ensure
    CompletionKit.config.runs_display_scope = nil
  end
```

(Confirm the API reference route path used by the existing spec; mirror it.)

- [ ] **Step 2: Run to verify it fails**

Run: `bundle exec rspec spec/requests/completion_kit/api_reference_spec.rb -e "display-scoped"`
Expected: FAIL.

- [ ] **Step 3: Implement**

`api_reference_controller.rb` line 5:

```ruby
      @recent_runs = Run.includes(:prompt).display_scoped.order(created_at: :desc).limit(10)
```

- [ ] **Step 4: Run to verify it passes**

Run: `bundle exec rspec spec/requests/completion_kit/api_reference_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/api_reference_controller.rb spec/requests/completion_kit/api_reference_spec.rb
git commit -m "Scope API reference recent-runs panel to display-scoped runs"
```

---

### Task 11: ProviderCredential stats

**Files:**
- Modify: `app/models/completion_kit/provider_credential.rb:68` (`judge_count`) and `:75-78` (`last_used_at`)
- Test: `spec/models/completion_kit/provider_credential_spec.rb`

**Interfaces:** Consumes `Run.display_scoped`.

- [ ] **Step 1: Write the failing tests**

```ruby
  describe "display-scoped run stats" do
    let(:credential) { create(:completion_kit_provider_credential, provider: "openai") }

    before { create(:completion_kit_model, provider: "openai", model_id: "gpt-4.1") }

    it "judge_count ignores runs hidden by runs_display_scope" do
      create(:completion_kit_run, judge_model: "gpt-4.1", created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(credential.judge_count).to eq(0)
    ensure
      CompletionKit.config.runs_display_scope = nil
    end

    it "last_used_at ignores runs hidden by runs_display_scope" do
      create(:completion_kit_run, judge_model: "gpt-4.1", status: "completed", created_at: 90.days.ago)
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(credential.last_used_at).to be_nil
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end
```

(Adjust factory names/attributes to match the real `:completion_kit_provider_credential` and `:completion_kit_model` factories — inspect `spec/factories` first. If a provider credential has required fields, supply them.)

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/models/completion_kit/provider_credential_spec.rb -e "display-scoped run stats"`
Expected: FAIL — judge_count 1, last_used_at present.

- [ ] **Step 3: Implement**

`provider_credential.rb` `judge_count` (line 68):

```ruby
      Run.where(judge_model: model_ids).display_scoped.distinct.count(:judge_model)
```

`last_used_at` (lines 75-78):

```ruby
      Run.where("prompt_id IN (:prompts) OR judge_model IN (:models)",
                prompts: prompt_scope, models: model_ids)
         .display_scoped
         .where.not(status: "pending")
         .maximum(:created_at)
```

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rspec spec/models/completion_kit/provider_credential_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/provider_credential.rb spec/models/completion_kit/provider_credential_spec.rb
git commit -m "Scope provider-credential judge_count and last_used_at to display-scoped runs"
```

---

### Task 12: Seam-2 child queries (trust panel + agreement examples)

**Files:**
- Modify: `app/services/completion_kit/metric_agreement_stats.rb:51` (base Agreement relation)
- Modify: `app/services/completion_kit/metric_agreement_examples.rb:32` (`agreements_for` base — DISPLAY only; do NOT touch `judge_examples_for`, lines 19-29)
- Modify: `app/views/completion_kit/agreements/_trust_panel.html.erb:7-12` (both queries)
- Test: `spec/services/completion_kit/metric_agreement_stats_spec.rb`, `spec/services/completion_kit/metric_agreement_examples_spec.rb`

**Interfaces:** Consumes `Run.visible_run_ids`. Child records (`Agreement`, `Response`) both have `run_id`.

- [ ] **Step 1: Write the failing tests**

`metric_agreement_stats_spec.rb` — add a second run and assert hidden-run verdicts drop out of the sample:

```ruby
  describe "with runs_display_scope" do
    it "excludes verdicts on display-scoped-out runs from the sample size" do
      hidden_run = create(:completion_kit_run, created_at: 90.days.ago)
      hidden_response = create(:completion_kit_response, run: hidden_run)
      create(:completion_kit_review, response: hidden_response, metric: metric, metric_name: metric.name, ai_score: 4)
      create(:completion_kit_agreement, run: hidden_run, response: hidden_response, metric: metric,
             metric_version: metric_version, verdict: "agree", created_by: SecureRandom.uuid)
      add_agreement(add_response(ai_score: 4), verdict: "agree")
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      expect(described_class.for(metric).sample_size).to eq(1)
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end
```

`metric_agreement_examples_spec.rb` — assert the display path drops hidden-run examples but `judge_examples_for` (seeding) keeps them. Build a corrected agreement on a hidden run; verify it appears in `judge_examples_for` and not in the display `for`/`disagreements_for` path. Model the setup on the existing examples spec; the key assertions:

```ruby
  describe "with runs_display_scope" do
    it "hides display examples on display-scoped-out runs but keeps them for judge seeding" do
      # set up a disagreement on a hidden run, corrected_score present, current metric version
      CompletionKit.config.runs_display_scope = -> { where(created_at: 30.days.ago..) }

      display = CompletionKit::MetricAgreementExamples.disagreements_for(metric)
      seeding = CompletionKit::MetricAgreementExamples.judge_examples_for(metric)

      expect(display.map { |e| e[:run_id] }).not_to include(hidden_run.id)
      expect(seeding.map { |e| e[:run_id] }).to include(hidden_run.id)
    ensure
      CompletionKit.config.runs_display_scope = nil
    end
  end
```

(Fill in the `hidden_run` / agreement setup using the existing examples spec's helpers so `judge_examples_for` returns the corrected example.)

- [ ] **Step 2: Run to verify they fail**

Run: `bundle exec rspec spec/services/completion_kit/metric_agreement_stats_spec.rb spec/services/completion_kit/metric_agreement_examples_spec.rb -e runs_display_scope`
Expected: FAIL — hidden verdicts counted / display includes hidden run.

- [ ] **Step 3: Implement**

`metric_agreement_stats.rb` line 51:

```ruby
      scope = Agreement.where(metric_id: @metric.id, run_id: Run.visible_run_ids)
```

`metric_agreement_examples.rb` `agreements_for` (line 32) — DISPLAY base only:

```ruby
      base = Agreement.where(metric_id: metric.id, verdict: verdict, run_id: Run.visible_run_ids)
```

Leave `judge_examples_for` (lines 19-29) unchanged.

`agreements/_trust_panel.html.erb` — line 7 (verdicted_ids) and line 8-12 (target response):

```erb
     verdicted_ids = CompletionKit::Agreement.where(metric_id: metric.id, created_by: created_by, metric_version_id: current_metric_version.id, run_id: CompletionKit::Run.visible_run_ids).pluck(:response_id)
     CompletionKit::Response.where(run_id: CompletionKit::Run.visible_run_ids).joins(:reviews)
       .where(reviews: { metric_id: metric.id, metric_version_id: current_metric_version.id })
       .where.not(reviews: { ai_score: nil })
       .where.not(id: verdicted_ids)
       .order(created_at: :desc).first
```

- [ ] **Step 4: Run to verify they pass**

Run: `bundle exec rspec spec/services/completion_kit/metric_agreement_stats_spec.rb spec/services/completion_kit/metric_agreement_examples_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/completion_kit/metric_agreement_stats.rb app/services/completion_kit/metric_agreement_examples.rb app/views/completion_kit/agreements/_trust_panel.html.erb spec/services/completion_kit/metric_agreement_stats_spec.rb spec/services/completion_kit/metric_agreement_examples_spec.rb
git commit -m "Scope trust-panel sample and agreement examples display to visible runs"
```

---

### Task 13: Docs + CHANGELOG

**Files:**
- Modify: `README.md` (the "Multi-tenant host apps (advanced)" section)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README**

Replace the runs-index hooks paragraph with the unified seam, documenting: `runs_display_scope` (zero-arg callable, `instance_exec`'d against a Run relation, must return a relation; applied at every run list/count/child site the engine owns); that it powers child-record visibility via `Run.visible_run_ids`; `runs_display_footer_partial` (rendered below runs lists on the index, prompt show, and dataset show, receiving the shown `runs` as a local); and the explicit non-targets (delete-cascade counts, id lookups, judge few-shot seeding, auto-name counters). Note the dashboard is host-managed.

- [ ] **Step 2: Update CHANGELOG**

Under `## [Unreleased]` add a `### Changed` entry: the 0.16.3 `runs_index_scope` / `runs_index_footer_partial` hooks are replaced by `runs_display_scope` / `runs_display_footer_partial`, now honored engine-wide (runs index, prompt/dataset show, compare picker, new-run tag defaults, API v1 index + `X-Total-Count`, MCP `runs_list`, API reference, provider-credential stats, trust-panel sample and agreement examples display). Few-shot judge seeding, delete-cascade counts, id lookups, and auto-name counters deliberately still see all runs.

- [ ] **Step 3: Full suite + coverage**

Run: `bundle exec rspec`
Expected: PASS, Line 100% / Branch 100%.

- [ ] **Step 4: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document engine-wide runs_display retention seams"
```

---

## Deliberately NOT scoped (record in PR description)

- `prompts/index.html.erb` `best_score` (`current_version_runs`) — an aggregate quality signal, not a run list/count. Left whole.
- `run.rb` auto-name counters, delete-cascade counts, id-addressed lookups, `judge_examples_for` seeding — see Global Constraints.
- Dashboard recent-runs/count and `DashboardStats` aggregates — host-managed / separate issue.

## Version

This replaces a public API shipped in 0.16.3. Cut as **0.17.0** (pre-1.0 minor may break). Follow the release runbook: bump `version.rb`, move CHANGELOG `[Unreleased]`, `bundle install` in BOTH engine root and `standalone/`, bump the smoke-spec `VERSION` assertion, commit `release 0.17.0`, `rake release`.
