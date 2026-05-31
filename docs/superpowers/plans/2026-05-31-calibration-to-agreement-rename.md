# Calibration to Agreement Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the "calibration" concept to "agreement" across the entire stack (model, table, services, controllers, routes, REST API, MCP tools, config, CSS, views, specs) as a clean break, with zero behavior change.

**Architecture:** A pure rename done in dependency order, one identifier-group per task, with the full suite green after every task. The word "calibration" is exclusive to this feature and does not overlap the verdict values (agree, disagree, borderline), so renaming it cannot alter the signal. The table is renamed in place (`rename_table`) to preserve existing data.

**Tech Stack:** Rails 8.1 engine (`CompletionKit`), RSpec + FactoryBot, SimpleCov 100% line+branch (`db/`, `app/views/`, `app/assets/` are filtered out, so the migration, view moves, and CSS renames are verified behaviorally). Postgres in `standalone/`, in-memory SQLite for the suite via the inline schema in `spec/rails_helper.rb`.

**Conventions for every task:** use `git mv` to rename files (preserves history); after editing, run the FULL suite `bundle exec rspec` and confirm green at 100% line and branch; finish each task with a targeted `grep` proving the renamed identifier is gone. House style: no code comments, no em dashes. The version bump to 0.12.0 and the lockfile bumps are NOT part of this plan; they happen at release time (the build merges to main unreleased, like the prior cycle). This plan only adds the CHANGELOG note under `## [Unreleased]`.

**Release-time reminder (not a task here):** when cutting 0.12.0, bump `lib/completion_kit/version.rb`, update the smoke spec's version assertion, run `bundle install` in BOTH the engine root and `standalone/`, and move the `## [Unreleased]` notes into a `## [0.12.0]` section.

---

## File renames overview (git mv)

- `app/models/completion_kit/calibration.rb` -> `agreement.rb`
- `app/models/completion_kit/calibration_math.rb` -> `agreement_math.rb`
- `app/services/completion_kit/metric_calibration_stats.rb` -> `metric_agreement_stats.rb`
- `app/services/completion_kit/metric_calibration_examples.rb` -> `metric_agreement_examples.rb`
- `app/controllers/completion_kit/calibrations_controller.rb` -> `agreements_controller.rb`
- `app/controllers/completion_kit/api/v1/calibrations_controller.rb` -> `agreements_controller.rb`
- `app/services/completion_kit/mcp_tools/calibrations.rb` -> `agreements.rb`
- `app/views/completion_kit/calibrations/` -> `app/views/completion_kit/agreements/` (`_buttons.html.erb`, `_trust_panel.html.erb`)
- `spec/factories/calibrations.rb` -> `agreements.rb`
- The matching spec files (`*calibration*_spec.rb`) -> `*agreement*_spec.rb`

---

## Task 1: Rename the service classes

`CalibrationMath`, `MetricCalibrationStats`, `MetricCalibrationExamples` are internal and still reference the (as-yet-unrenamed) `Calibration` model, so they rename cleanly first.

**Files:** the three service files above and their specs, plus every caller (`metrics_controller`, `mcp_tools/judges.rb`, the `_trust_panel` partial, `dashboard_stats`, and any spec that names these classes).

- [ ] **Step 1: Rename the files**

```bash
cd /Users/damien/Work/homemade/completion-kit
git mv app/models/completion_kit/calibration_math.rb app/models/completion_kit/agreement_math.rb
git mv app/services/completion_kit/metric_calibration_stats.rb app/services/completion_kit/metric_agreement_stats.rb
git mv app/services/completion_kit/metric_calibration_examples.rb app/services/completion_kit/metric_agreement_examples.rb
# rename their spec files too:
git mv spec/models/completion_kit/calibration_math_spec.rb spec/models/completion_kit/agreement_math_spec.rb 2>/dev/null || true
git mv spec/services/completion_kit/metric_calibration_stats_spec.rb spec/services/completion_kit/metric_agreement_stats_spec.rb 2>/dev/null || true
git mv spec/services/completion_kit/metric_calibration_examples_spec.rb spec/services/completion_kit/metric_agreement_examples_spec.rb 2>/dev/null || true
```
(Confirm the exact spec paths first with `ls spec/**/*calibration*`; rename whatever exists.)

- [ ] **Step 2: Rename the class identifiers and all references**

Apply these exact identifier replacements in `app/` and `spec/` (do NOT touch `db/` here): `CalibrationMath` -> `AgreementMath`, `MetricCalibrationStats` -> `MetricAgreementStats`, `MetricCalibrationExamples` -> `MetricAgreementExamples`. The class definitions live in the renamed files; the references live in callers. Find every reference with:

```bash
grep -rn "CalibrationMath\|MetricCalibrationStats\|MetricCalibrationExamples" app spec
```
Update each hit (class definition lines and all callers). In `app/services/completion_kit/mcp_tools/judges.rb`, also change the tool description text "calibration stats" to "agreement stats".

- [ ] **Step 3: Run the suite**

Run: `bundle exec rspec`
Expected: green at 100% line and branch. These classes still reference `CompletionKit::Calibration` (unchanged), so nothing else breaks.

- [ ] **Step 4: Verify and commit**

```bash
grep -rn "CalibrationMath\|MetricCalibrationStats\|MetricCalibrationExamples" app lib spec   # expect: no matches
git add -A
git commit -m "Rename calibration stat/math/example services to agreement"
```

---

## Task 2: Rename the model, table, factory, and association

The core atomic rename: the `Calibration` model maps to `completion_kit_calibrations`, so the class and table must rename together, along with the factory and every reference.

**Files:** `app/models/completion_kit/calibration.rb`, `spec/factories/calibrations.rb`, `app/models/completion_kit/metric_version.rb` (the association), a new engine migration, `standalone/db/schema.rb` + installed copy, `spec/rails_helper.rb` (inline schema), the model spec, and every `CompletionKit::Calibration` / `:completion_kit_calibration` reference across `app/` and `spec/`.

- [ ] **Step 1: Write the rename_table migration**

Create `db/migrate/20260531000004_rename_calibrations_to_agreements.rb`:

```ruby
class RenameCalibrationsToAgreements < ActiveRecord::Migration[8.1]
  CALIBRATION_INDEXES = {
    "index_ck_calibrations_on_metric_id" => "index_ck_agreements_on_metric_id",
    "index_ck_calibrations_on_metric_version_id" => "index_ck_agreements_on_metric_version_id",
    "index_ck_calibrations_on_response_id" => "index_ck_agreements_on_response_id",
    "index_ck_calibrations_on_run_id" => "index_ck_agreements_on_run_id",
    "index_ck_calibrations_on_response_metric_user" => "index_ck_agreements_on_response_metric_user"
  }.freeze

  def up
    rename_table :completion_kit_calibrations, :completion_kit_agreements
    CALIBRATION_INDEXES.each { |old_name, new_name| rename_index :completion_kit_agreements, old_name, new_name }
  end

  def down
    CALIBRATION_INDEXES.each { |old_name, new_name| rename_index :completion_kit_agreements, new_name, old_name }
    rename_table :completion_kit_agreements, :completion_kit_calibrations
  end
end
```

- [ ] **Step 2: Rename the model and factory**

```bash
git mv app/models/completion_kit/calibration.rb app/models/completion_kit/agreement.rb
git mv spec/factories/calibrations.rb spec/factories/agreements.rb
git mv spec/models/completion_kit/calibration_spec.rb spec/models/completion_kit/agreement_spec.rb 2>/dev/null || true
```

In `agreement.rb`: `class Calibration` -> `class Agreement` (the constant `VERDICTS` and all method bodies stay; only the class name changes).

In `spec/factories/agreements.rb`: factory `:completion_kit_calibration` -> `:completion_kit_agreement`, and `class: "CompletionKit::Calibration"` -> `"CompletionKit::Agreement"`.

In `app/models/completion_kit/metric_version.rb`: `has_many :calibrations, dependent: :destroy` -> `has_many :agreements, dependent: :destroy`.

- [ ] **Step 3: Update every model/factory reference**

```bash
grep -rn "CompletionKit::Calibration\b\|Calibration\.\|completion_kit_calibration\b\|:calibrations\|\.calibrations\b" app spec
```
Replace `CompletionKit::Calibration` -> `CompletionKit::Agreement`, bare `Calibration` (model) -> `Agreement`, `:completion_kit_calibration` -> `:completion_kit_agreement`, and association uses `.calibrations` / `:calibrations` -> `.agreements` / `:agreements`. (Controllers and MCP still have their own class names; those rename in later tasks. Here, only update their references TO the model, e.g. `Calibration.all` -> `Agreement.all`.)

- [ ] **Step 4: Update the inline test schema**

In `spec/rails_helper.rb`: `create_table :completion_kit_calibrations` -> `create_table :completion_kit_agreements`, and the explicit index `name: "index_ck_calibrations_on_response_metric_user"` -> `name: "index_ck_agreements_on_response_metric_user"`. (The `t.references` auto-index names follow the renamed table automatically.)

- [ ] **Step 5: Run the suite**

Run: `bundle exec rspec`
Expected: green at 100%. If a reference was missed, a `NameError` or a `no such table` points right at it; fix and rerun.

- [ ] **Step 6: Apply the migration to standalone and verify data is preserved**

```bash
cd standalone && DISABLE_SPRING=1 bin/rails runner 'puts "before: #{CompletionKit::Agreement.count}"'
DISABLE_SPRING=1 bin/rails completion_kit:install:migrations
DISABLE_SPRING=1 bin/rails db:migrate
DISABLE_SPRING=1 bin/rails runner 'puts "after: #{CompletionKit::Agreement.count}"'
```
Expected: the before and after counts are identical (rename preserved the rows). `standalone/db/schema.rb` now shows `create_table "completion_kit_agreements"` with `index_ck_agreements_*` names and the four `add_foreign_key "completion_kit_agreements", ...` lines.

- [ ] **Step 7: Verify and commit**

```bash
cd /Users/damien/Work/homemade/completion-kit
grep -rni "calibration" app/models spec/models/completion_kit/agreement_spec.rb spec/factories/agreements.rb   # expect: no matches
git add -A
git commit -m "Rename Calibration model and table to Agreement"
```

---

## Task 3: Rename the controllers, routes, and views directory

**Files:** both controllers (web + API), `config/routes.rb` (3 blocks), the views directory move, and every path-helper / render-path / `ensure_calibration_enabled` reference in views and specs.

- [ ] **Step 1: Rename controller and view files**

```bash
git mv app/controllers/completion_kit/calibrations_controller.rb app/controllers/completion_kit/agreements_controller.rb
git mv app/controllers/completion_kit/api/v1/calibrations_controller.rb app/controllers/completion_kit/api/v1/agreements_controller.rb
git mv app/views/completion_kit/calibrations app/views/completion_kit/agreements
git mv spec/requests/completion_kit/calibrations_spec.rb spec/requests/completion_kit/agreements_spec.rb 2>/dev/null || true
git mv spec/requests/completion_kit/api/v1/calibrations_spec.rb spec/requests/completion_kit/api/v1/agreements_spec.rb 2>/dev/null || true
```
(Confirm exact spec paths with `ls spec/**/*calibration*` and rename whatever exists.)

- [ ] **Step 2: Rename the controller classes and internals**

- Web: `class CalibrationsController` -> `class AgreementsController`.
- API: `class CalibrationsController < BaseController` -> `class AgreementsController < BaseController`; method `ensure_calibration_enabled` -> `ensure_agreement_enabled` (and its `before_action`); the error string `"Calibration disabled"` -> `"Agreement disabled"`; `CompletionKit.config.judge_calibration_enabled` -> `judge_agreement_enabled` (note: the config rename itself lands in Task 5, but update the reference here and it will be consistent once Task 5 renames the accessor; to keep this task green, defer the `judge_calibration_enabled` reference change to Task 5 and leave it untouched here).

To keep Task 3 green, leave `judge_calibration_enabled` references alone for now (Task 5 owns the config). Rename only the controller classes, the `ensure_*` method name, and the user-facing string.

- [ ] **Step 3: Update routes**

In `config/routes.rb`, change all three `resources :calibrations` to `resources :agreements` (lines around 44, 78, 96). This automatically remaps the path helpers (`run_response_calibrations_path` -> `run_response_agreements_path`, the nested API helper, and `api_v1_calibrations_path` -> `api_v1_agreements_path`).

- [ ] **Step 4: Update path helpers and render paths**

```bash
grep -rn "calibrations_path\|calibrations_url\|completion_kit/calibrations/\|\"calibrations/\|calibration" app/views app/controllers spec | grep -vi "judge_calibration_enabled"
```
Replace `*calibrations_path`/`*calibrations_url` helper names with `*agreements_*`, and render paths `completion_kit/calibrations/buttons` -> `completion_kit/agreements/buttons` and `completion_kit/calibrations/trust_panel` -> `completion_kit/agreements/trust_panel` (these are referenced from `responses/show.html.erb` and `metrics/show.html.erb`). Leave `judge_calibration_enabled` for Task 5.

- [ ] **Step 5: Run the suite, verify, commit**

```bash
bundle exec rspec   # expect green at 100%
grep -rn "CalibrationsController\|calibrations_path\|completion_kit/calibrations" app spec config   # expect: no matches
git add -A
git commit -m "Rename calibration controllers, routes, and views to agreement"
```

---

## Task 4: Rename CSS classes, remaining visible text, and add the link anchor

**Files:** `app/assets/stylesheets/completion_kit/application.css`, the agreement view partials, `responses/show.html.erb`, `metrics/show.html.erb`, and any spec asserting `ck-calibration*` or the link text.

- [ ] **Step 1: Rename the CSS classes**

Replace `ck-calibration` -> `ck-agreement` everywhere (around 51 occurrences across `app/assets/stylesheets/completion_kit/application.css` and the view partials). Find with:

```bash
grep -rn "ck-calibration" app/assets app/views spec
```
Update the stylesheet definitions and every `class="ck-calibration..."` usage in the views, plus any spec asserting those class strings.

- [ ] **Step 2: Relabel the verdict-row link and point it at the Agreement card**

In `app/views/completion_kit/agreements/_buttons.html.erb`, the link currently reads `Calibration ->` and targets `metric_path(metric)`. Change the visible text to `Agreement ->` and the target to `metric_path(metric, anchor: "agreement")`.

In `app/views/completion_kit/agreements/_trust_panel.html.erb`, add `id="agreement"` to the partial's root container element (the Agreement card) so the anchor resolves.

- [ ] **Step 3: Sweep remaining visible "calibration" text**

```bash
grep -rni "calibration" app/views
```
Replace any remaining user-visible "Calibration" / "calibration" wording with "Agreement" / "agreement". (Do not touch verdict values agree/disagree/borderline; they do not contain the word.)

- [ ] **Step 4: Run the suite, verify, commit**

```bash
bundle exec rspec   # expect green at 100%
grep -rni "calibration" app/assets app/views   # expect: no matches
git add -A
git commit -m "Rename calibration CSS and copy to agreement; anchor the verdict-row link"
```

---

## Task 5: Rename the MCP tools and the config flag

**Files:** `app/services/completion_kit/mcp_tools/agreements.rb` (the moved file), the MCP tool registry/wiring, `lib/completion_kit.rb` (config), the API controller's config reference (deferred from Task 3), and their specs.

- [ ] **Step 1: Rename the MCP tool file and module**

```bash
git mv app/services/completion_kit/mcp_tools/calibrations.rb app/services/completion_kit/mcp_tools/agreements.rb
git mv spec/services/completion_kit/mcp_tools/calibrations_spec.rb spec/services/completion_kit/mcp_tools/agreements_spec.rb 2>/dev/null || true
```

In `agreements.rb`: `module Calibrations` -> `module Agreements`; tool keys `"calibrations_list"` -> `"agreements_list"` and `"calibrations_create"` -> `"agreements_create"`; the descriptions ("List calibrations...", "Upsert a calibration...") reworded to "agreement(s)"; `CompletionKit::Calibration` was already renamed to `Agreement` in Task 2, so confirm those references read `Agreement`.

- [ ] **Step 2: Update the MCP registry/wiring**

```bash
grep -rn "McpTools::Calibrations\|calibrations_list\|calibrations_create\|Calibrations\b" app spec
```
Update wherever the `McpTools::Calibrations` module and its tool names are registered/dispatched (the MCP server's tool registry) to the `Agreements` names. Update any spec calling `"calibrations_list"` / `"calibrations_create"` to the new names.

- [ ] **Step 3: Rename the config flag**

In `lib/completion_kit.rb`: `attr_accessor :judge_calibration_enabled` -> `:judge_agreement_enabled` (line ~15) and `@judge_calibration_enabled = true` -> `@judge_agreement_enabled = true` (line ~32). Then update every reader:

```bash
grep -rn "judge_calibration_enabled" app lib spec
```
Replace all with `judge_agreement_enabled` (this includes the API controller's `ensure_agreement_enabled` from Task 3, the metric and response views that gate on it, and any spec configuring it).

- [ ] **Step 4: Run the suite, verify, commit**

```bash
bundle exec rspec   # expect green at 100%
grep -rn "judge_calibration_enabled\|McpTools::Calibrations\|calibrations_list\|calibrations_create" app lib spec   # expect: no matches
git add -A
git commit -m "Rename calibration MCP tools and config flag to agreement"
```

---

## Task 6: Final sweep, suite, and CHANGELOG

- [ ] **Step 1: Global grep for any remnant**

```bash
grep -rni "calibration" app lib config db spec
```
Expected: NO matches anywhere. (The verdict values agree/disagree/borderline do not contain the word, so zero is achievable.) If anything remains, rename it and rerun. Note: `db/migrate/20260531000004_rename_calibrations_to_agreements.rb` legitimately contains "calibration" in its class name, the `CALIBRATION_INDEXES` map, and the old index-name strings; that is expected and correct (it is the migration that performs the rename). Exclude it from the "must be zero" expectation: `grep -rni "calibration" app lib config spec` (without `db`) must be zero; within `db`, only that one migration may mention it.

- [ ] **Step 2: Full suite**

Run: `bundle exec rspec`
Expected: green at 100% line and branch.

- [ ] **Step 3: Add the CHANGELOG breaking note**

In `CHANGELOG.md`, under the `## [Unreleased]` section, add:

```markdown
### Changed (breaking)
- Renamed the "calibration" concept to "agreement" throughout. The `Calibration` model and `completion_kit_calibrations` table are now `Agreement` / `completion_kit_agreements`. The REST API resource is now `/agreements` (was `/calibrations`), the MCP tools are `agreements_list` / `agreements_create` (were `calibrations_*`), and the config flag is `judge_agreement_enabled` (was `judge_calibration_enabled`). No aliases are kept; update API and MCP callers accordingly.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "Note the Calibration to Agreement rename in the changelog"
```

---

## Self-Review

**Spec coverage:**
- Naming map (model, table, services, controllers, routes, API, views, CSS, config, MCP, association, factory, specs): Tasks 1-5 cover each row. Verified each identifier in the spec's table maps to a task.
- Clean break (remove old routes/tools/config, no aliases): Tasks 3 and 5 rename in place with no alias left behind; Task 6's grep proves the old names are gone.
- Stays unchanged (verdict values, behavior): no task touches verdict strings or method bodies beyond identifier references; called out in Tasks 2 and 4.
- Table migration preserving data: Task 2, Step 6 verifies equal row counts.
- Verdict-row link relabel + anchor: Task 4, Step 2.
- Staged with suite green between: every task ends with a full-suite run.
- Version 0.12.0 + CHANGELOG: CHANGELOG note in Task 6; the version bump itself is correctly deferred to release time (stated in the header), matching the prior cycle.

**Placeholder scan:** No TBD or vague steps. The one cross-task ordering nuance (the `judge_calibration_enabled` reference in the API controller is deferred from Task 3 to Task 5 so Task 3 stays green) is stated explicitly in both tasks rather than left implicit.

**Type/name consistency:** `Agreement`, `AgreementMath`, `MetricAgreementStats`, `MetricAgreementExamples`, `AgreementsController`, `completion_kit_agreements`, `index_ck_agreements_*`, `judge_agreement_enabled`, `agreements_list`/`agreements_create`, `:completion_kit_agreement`, `has_many :agreements`, and the `#agreement` anchor are used consistently across tasks and match the spec's naming map.
