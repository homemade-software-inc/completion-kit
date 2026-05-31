# Metric Version Provenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make metric version provenance honest and visible: reverting returns to the existing version in place (keeping its reviews and signal), and every scored judgement reliably resolves the metric version the judge used so the version chip renders.

**Architecture:** Part 1 replaces `MetricVersion#revert!` (which minted a copy) with the existing `publish!` at all three call sites, so reverting just makes the target version current again. Part 2 makes the review-to-version link reliable: a required model association, a data backfill that re-points orphaned reviews to each metric's current version, and a database foreign key with `on_delete: :nullify`. The version chip on the response page then renders with no view change.

**Tech Stack:** Rails 8.1 engine (namespaced `CompletionKit`), RSpec + FactoryBot, SimpleCov at 100 percent line and branch (db/ and app/views/ are filtered out, so migrations and views are verified by behavior, not coverage), Postgres in the standalone host, SQLite in-memory for the suite via the inline schema in `spec/rails_helper.rb`.

**Refinements from the spec discovered during planning (carry these, they override the spec where they differ):**
- Foreign key uses `on_delete: :nullify`, not `:restrict`. `Metric has_many :metric_versions, dependent: :destroy` and `has_many :reviews, dependent: :nullify`, so deleting a metric destroys its versions while reviews still reference them. `restrict` would block metric deletion; `nullify` keeps reviews alive with a null version, matching how reviews already survive metric deletion.
- No stamping in the job's failure or placeholder paths. The column stays nullable and those rows save with `validate: false` and never show a chip, so the success path (which already stamps) plus the backfill and the foreign key are enough.
- The review factory sets `metric_version { metric && CompletionKit::MetricVersion.ensure_current_for(metric) }` so built reviews carry a version tied to their own metric.

---

## File Structure

- `app/models/completion_kit/metric_version.rb` (remove `revert!`)
- `app/models/completion_kit/review.rb` (required association)
- `app/controllers/completion_kit/metrics_controller.rb` (`publish_draft` reverts in place + flash copy)
- `app/controllers/completion_kit/api/v1/metric_versions_controller.rb` (`publish` reverts in place)
- `app/services/completion_kit/mcp_tools/metric_versions.rb` (`publish` reverts in place)
- `app/views/completion_kit/metrics/show.html.erb` (Make current confirm copy)
- `spec/factories/reviews.rb` (associate a metric version)
- `db/migrate/20260531000002_backfill_review_metric_versions.rb` (new, data backfill)
- `db/migrate/20260531000003_add_metric_version_fk_to_reviews.rb` (new, foreign key)
- `standalone/db/migrate/*.completion_kit.rb` and `standalone/db/schema.rb` (installed copies + regenerated schema)
- Specs rewritten in: `spec/requests/completion_kit/metrics_judge_versions_spec.rb`, `spec/requests/completion_kit/api/v1/metric_versions_spec.rb`, `spec/services/completion_kit/mcp_tools/metric_versions_spec.rb`, `spec/models/completion_kit/metric_version_spec.rb`, plus a response-page chip assertion in `spec/requests/completion_kit/responses_spec.rb`

The inline test schema in `spec/rails_helper.rb` is unchanged: `completion_kit_reviews.metric_version_id` is already a nullable bigint with an index, and the inline schema declares no foreign keys (matching the existing pattern, where the calibrations foreign keys live only in the standalone schema).

---

## Task 1: Revert in place (web controller)

**Files:**
- Modify: `app/controllers/completion_kit/metrics_controller.rb:157-184`
- Test: `spec/requests/completion_kit/metrics_judge_versions_spec.rb:128-160`

- [ ] **Step 1: Rewrite the two revert request specs**

Replace the existing `it "lets the user revert to an older published version via Make current"` block (lines 128-147) and the `it "carries a revert-specific flash ..."` block (lines 149-160) with:

```ruby
  it "reverts to an older published version in place via Make current, creating no new version" do
    edit_metric_via_form(instruction: "v2 instruction")
    draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id).order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: draft.id }
    follow_redirect!

    older = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).first
    expect(older.current?).to be(false)
    expect(older.published?).to be(true)

    expect {
      post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    }.not_to change { CompletionKit::MetricVersion.where(metric_id: metric.id).count }

    expect(older.reload.current?).to be(true)
    expect(metric.reload.instruction).to eq(older.instruction)
    expect(CompletionKit::MetricVersion.where(metric_id: metric.id, source: "revert").count).to eq(0)
  end

  it "carries an in-place revert flash naming the version returned to and the one left behind" do
    edit_metric_via_form(instruction: "v2 instruction")
    new_draft = CompletionKit::MetricVersion.drafts.where(metric_id: metric.id, source: "edit").order(:created_at).last
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: new_draft.id }
    follow_redirect!

    older = CompletionKit::MetricVersion.where(metric_id: metric.id).order(:version_number).first
    post "/completion_kit/metrics/#{metric.id}/publish_draft", params: { draft_id: older.id }
    follow_redirect!
    expect(response.body).to include("is back on #{older.version_label}")
    expect(response.body).to include("stay with that version")
  end
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `bundle exec rspec spec/requests/completion_kit/metrics_judge_versions_spec.rb -e "in place"`
Expected: FAIL. The first fails because today the count changes by 1 (a revert audit row is minted); the second fails because the flash still reads "Reverted ... (logged as ...)".

- [ ] **Step 3: Rewrite `publish_draft` to revert in place**

Replace the body from `if reverting` through the closing `end` (lines 174-183) with a single `publish!` and a branch only for the flash:

```ruby
      version.publish!

      if reverting
        redirect_to metric_path(@metric),
                    notice: "#{@metric.name} is back on #{version.version_label}. Its reviews count again; the ones you gave on #{previously_current.version_label} stay with that version."
      else
        redirect_to metric_path(@metric),
                    notice: "#{@metric.name} #{version.version_label} is now the published version."
      end
```

Leave lines 170-172 (`was_published_already`, `reverting`, `previously_current`) as they are; `previously_current` must be captured before `publish!` flips the current flags, and it is always present in the reverting branch because a published non-current version implies another version is current.

- [ ] **Step 4: Run the specs to verify they pass**

Run: `bundle exec rspec spec/requests/completion_kit/metrics_judge_versions_spec.rb`
Expected: PASS, including the unchanged "publishes the latest draft" and "flashes an alert when there is no draft" cases.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/completion_kit/metrics_controller.rb spec/requests/completion_kit/metrics_judge_versions_spec.rb
git commit -m "Revert metric versions in place from the web controller"
```

---

## Task 2: Revert in place (API and MCP)

**Files:**
- Modify: `app/controllers/completion_kit/api/v1/metric_versions_controller.rb:16-24`
- Modify: `app/services/completion_kit/mcp_tools/metric_versions.rb:48-57`
- Test: `spec/requests/completion_kit/api/v1/metric_versions_spec.rb:51-67`
- Test: `spec/services/completion_kit/mcp_tools/metric_versions_spec.rb:31-49`

- [ ] **Step 1: Rewrite the API revert spec**

Replace the `it "reverts to an older published version by recording a new revert audit row"` block (lines 51-67) with:

```ruby
    it "reverts to an older published version in place, creating no new version" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!
      expect(v1.reload.current).to be(false)

      expect {
        post "/completion_kit/api/v1/metrics/#{metric.id}/metric_versions/#{v1.id}/publish", headers: headers
      }.not_to change { CompletionKit::MetricVersion.where(metric_id: metric.id).count }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(v1.id)
      expect(body["current"]).to be(true)
      expect(body["source"]).not_to eq("revert")
      expect(metric.reload.instruction).to eq("v1 instruction")
      expect(v2.reload.current).to be(false)
    end
```

- [ ] **Step 2: Rewrite the MCP revert spec**

Replace the `it "reverts to an older published version by writing a new revert audit row"` block (lines 31-49) with:

```ruby
    it "reverts to an older published version in place, creating no new version" do
      v1 = CompletionKit::MetricVersion.ensure_current_for(metric)
      v2 = CompletionKit::MetricVersion.create!(metric: metric, instruction: "v2", rubric_bands: metric.rubric_bands || [], state: "draft", source: "edit")
      v2.publish!

      result = nil
      expect {
        result = CompletionKit::McpTools::MetricVersions.call("metric_versions_publish", { "metric_version_id" => v1.id })
      }.not_to change { CompletionKit::MetricVersion.where(metric_id: metric.id).count }
      parsed = JSON.parse(result[:content].first[:text])

      expect(parsed["id"]).to eq(v1.id)
      expect(parsed["current"]).to be(true)
      expect(parsed["source"]).not_to eq("revert")
      expect(metric.reload.instruction).to eq("v1 instruction")
      expect(v2.reload.current).to be(false)
    end
```

- [ ] **Step 3: Run both specs to verify they fail**

Run: `bundle exec rspec spec/requests/completion_kit/api/v1/metric_versions_spec.rb spec/services/completion_kit/mcp_tools/metric_versions_spec.rb -e "in place"`
Expected: FAIL. Both currently mint a revert row, so the count changes and the returned `id` is the new row, not `v1`.

- [ ] **Step 4: Rewrite both publish actions to revert in place**

In `app/controllers/completion_kit/api/v1/metric_versions_controller.rb`, replace the `publish` method body (lines 17-23) with:

```ruby
        def publish
          @version.publish!
          render json: @version.reload
        end
```

In `app/services/completion_kit/mcp_tools/metric_versions.rb`, replace the `publish` method body (lines 49-56) with:

```ruby
      def self.publish(args)
        version = CompletionKit::MetricVersion.find(args["metric_version_id"])
        version.publish!
        text_result(version.reload.as_json)
      end
```

- [ ] **Step 5: Run both specs to verify they pass**

Run: `bundle exec rspec spec/requests/completion_kit/api/v1/metric_versions_spec.rb spec/services/completion_kit/mcp_tools/metric_versions_spec.rb`
Expected: PASS, including the unchanged draft-publish cases.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/completion_kit/api/v1/metric_versions_controller.rb app/services/completion_kit/mcp_tools/metric_versions.rb spec/requests/completion_kit/api/v1/metric_versions_spec.rb spec/services/completion_kit/mcp_tools/metric_versions_spec.rb
git commit -m "Revert metric versions in place from the API and MCP"
```

---

## Task 3: Remove `MetricVersion#revert!`

**Files:**
- Modify: `app/models/completion_kit/metric_version.rb:86-100`
- Test: `spec/models/completion_kit/metric_version_spec.rb:153-159`

- [ ] **Step 1: Delete the model spec block for `#revert!`**

Remove the entire `describe "#revert!" do ... end` block (lines 153-159). It is the only spec that exercised `revert!`.

- [ ] **Step 2: Confirm no other reference remains**

Run: `grep -rn "revert!" app lib spec`
Expected: no matches (Tasks 1 and 2 already removed the three callers; this step guards against a missed reference before deleting the method).

- [ ] **Step 3: Delete the `revert!` method**

Remove the `def revert! ... end` method (lines 86-100) from `app/models/completion_kit/metric_version.rb`.

- [ ] **Step 4: Run the model spec and the full version surface**

Run: `bundle exec rspec spec/models/completion_kit/metric_version_spec.rb`
Expected: PASS. `publish!` coverage is unaffected; the removed method takes its only covering test with it.

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/metric_version.rb spec/models/completion_kit/metric_version_spec.rb
git commit -m "Remove MetricVersion#revert! now that revert publishes in place"
```

---

## Task 4: Require a metric version on every judgement

**Files:**
- Modify: `app/models/completion_kit/review.rb:7`
- Modify: `spec/factories/reviews.rb`
- Test: `spec/models/completion_kit/review_spec.rb` (add a validation example)

- [ ] **Step 1: Write the failing validation test**

Add to `spec/models/completion_kit/review_spec.rb` inside the top-level describe:

```ruby
  describe "metric version requirement" do
    it "is invalid without a metric version when it has a metric" do
      response = create(:completion_kit_response)
      metric = create(:completion_kit_metric)
      review = build(:completion_kit_review, response: response, metric: metric, metric_version: nil)
      expect(review).not_to be_valid
      expect(review.errors[:metric_version]).to be_present
    end

    it "is valid with a metric version" do
      expect(build(:completion_kit_review)).to be_valid
    end
  end
```

- [ ] **Step 2: Run it to verify the first example fails**

Run: `bundle exec rspec spec/models/completion_kit/review_spec.rb -e "metric version requirement"`
Expected: FAIL on the first example. Today `belongs_to :metric_version, optional: true` lets a nil version pass.

- [ ] **Step 3: Make the association required and fix the factory**

In `app/models/completion_kit/review.rb` line 7, change:

```ruby
    belongs_to :metric_version
```

In `spec/factories/reviews.rb`, add the version association so built reviews carry one tied to their own metric. The full factory becomes:

```ruby
FactoryBot.define do
  factory :completion_kit_review, class: "CompletionKit::Review" do
    association :response, factory: :completion_kit_response
    association :metric, factory: :completion_kit_metric
    metric_version { metric && CompletionKit::MetricVersion.ensure_current_for(metric) }
    metric_name { "Quality" }
    instruction { "Rate the response quality." }
    status { "succeeded" }
    ai_score { 4.0 }
    ai_feedback { "Good response." }
  end
end
```

- [ ] **Step 4: Run the new test, then the full suite to surface fallout**

Run: `bundle exec rspec spec/models/completion_kit/review_spec.rb -e "metric version requirement"`
Expected: PASS.

Run: `bundle exec rspec`
Expected: Some other specs may now fail. Two predictable causes, both to fix in this step:
1. A spec that creates a metric-less review through validations. Change it to build a review with a metric, or save it with `save(validate: false)` if the test specifically needs a metric-less row.
2. A spec that asserts an exact `MetricVersion` count for a metric and is thrown off by the factory now calling `ensure_current_for`. Adjust the expectation, or pass an existing current version via `metric_version:` so no new one is created.

Work through the failures until the suite is green at 100 percent line and branch coverage.

- [ ] **Step 5: Commit**

```bash
git add app/models/completion_kit/review.rb spec/factories/reviews.rb spec/models/completion_kit/review_spec.rb
git commit -m "Require a metric version on every review"
```

---

## Task 5: Backfill orphaned reviews to a real version

**Files:**
- Create: `db/migrate/20260531000002_backfill_review_metric_versions.rb`
- Modify (generated): `standalone/db/migrate/*_backfill_review_metric_versions.completion_kit.rb`, `standalone/db/schema.rb`

This migration is in `db/`, which SimpleCov filters out, so it has no coverage test. It is verified by running it against the standalone database (Step 4) and confirming the dev reviews resolve.

- [ ] **Step 1: Write the backfill migration**

```ruby
class BackfillReviewMetricVersions < ActiveRecord::Migration[8.1]
  def up
    quoted_true = ActiveRecord::Base.connection.quote(true)
    now = ActiveRecord::Base.connection.quote(Time.current)

    execute <<~SQL
      INSERT INTO completion_kit_metric_versions
        (metric_id, instruction, rubric_bands, current, state, version_number, published_at, created_at, updated_at)
      SELECT m.id, m.instruction, m.rubric_bands, #{quoted_true}, 'published', 1, #{now}, #{now}, #{now}
      FROM completion_kit_metrics m
      WHERE NOT EXISTS (
        SELECT 1 FROM completion_kit_metric_versions mv WHERE mv.metric_id = m.id
      )
    SQL

    execute <<~SQL
      UPDATE completion_kit_reviews
      SET metric_version_id = (
        SELECT mv.id FROM completion_kit_metric_versions mv
        WHERE mv.metric_id = completion_kit_reviews.metric_id AND mv.current = #{quoted_true}
        LIMIT 1
      )
      WHERE metric_id IS NOT NULL
        AND (
          metric_version_id IS NULL
          OR metric_version_id NOT IN (SELECT id FROM completion_kit_metric_versions)
        )
    SQL
  end

  def down
    # Re-pointing orphaned reviews is not reversible.
  end
end
```

- [ ] **Step 2: Install the migration into the standalone host**

Run: `cd standalone && bin/rails completion_kit:install:migrations`
Expected: a `*_backfill_review_metric_versions.completion_kit.rb` copy appears under `standalone/db/migrate`.

- [ ] **Step 3: Run the migration in the standalone host**

Run: `cd standalone && DISABLE_SPRING=1 bin/rails db:migrate`
Expected: completes, and `standalone/db/schema.rb` advances its version line. Schema structure is unchanged (this is a data migration).

- [ ] **Step 4: Verify the dev data is repaired**

Run:
```bash
cd standalone && DISABLE_SPRING=1 bin/rails runner '
existing = CompletionKit::MetricVersion.pluck(:id).to_set
withid = CompletionKit::Review.where.not(metric_version_id: nil).to_a
dangling = withid.count { |r| !existing.include?(r.metric_version_id) }
puts "reviews with version: #{withid.size}  still dangling: #{dangling}"
'
```
Expected: `still dangling: 0`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20260531000002_backfill_review_metric_versions.rb standalone/db/migrate standalone/db/schema.rb
git commit -m "Backfill reviews that point at deleted metric versions"
```

---

## Task 6: Foreign key on `reviews.metric_version_id`

**Files:**
- Create: `db/migrate/20260531000003_add_metric_version_fk_to_reviews.rb`
- Modify (generated): `standalone/db/migrate/*_add_metric_version_fk_to_reviews.completion_kit.rb`, `standalone/db/schema.rb`

Also in `db/`, so no coverage test. The inline test schema in `spec/rails_helper.rb` is not touched: it declares no foreign keys, matching the existing calibrations pattern, and the suite relies on the model validation from Task 4. Must run after Task 5 so no row violates the constraint.

- [ ] **Step 1: Write the foreign key migration**

```ruby
class AddMetricVersionFkToReviews < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :completion_kit_reviews, :completion_kit_metric_versions,
                    column: :metric_version_id, on_delete: :nullify
  end
end
```

- [ ] **Step 2: Install and run it in the standalone host**

Run: `cd standalone && bin/rails completion_kit:install:migrations`
Run: `cd standalone && DISABLE_SPRING=1 bin/rails db:migrate`
Expected: the migration succeeds because Task 5 left no dangling `metric_version_id`. `standalone/db/schema.rb` gains the line `add_foreign_key "completion_kit_reviews", "completion_kit_metric_versions", column: "metric_version_id", on_delete: :nullify`.

- [ ] **Step 3: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS at 100 percent. The suite uses the inline SQLite schema, which has no foreign key, so this migration does not change test behavior; this step confirms nothing regressed.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260531000003_add_metric_version_fk_to_reviews.rb standalone/db/migrate standalone/db/schema.rb
git commit -m "Add a foreign key on reviews.metric_version_id with nullify on delete"
```

---

## Task 7: Confirm the version chip renders

**Files:**
- Test: `spec/requests/completion_kit/responses_spec.rb`

No production code changes here. The chip in `responses/show.html.erb:107-114` already renders whenever `review.metric_version` resolves; Tasks 4 to 6 make that reliable. This task locks the behavior with a request spec and confirms it on the dev page.

- [ ] **Step 1: Write a chip request spec**

Add to `spec/requests/completion_kit/responses_spec.rb` (create the file with the standard `require "rails_helper"` and a `RSpec.describe "Responses", type: :request do` wrapper if it does not exist):

```ruby
  it "shows the metric version chip for a judged review" do
    run = create(:completion_kit_run, judge_model: "gpt-4.1-mini")
    response_row = create(:completion_kit_response, run: run)
    metric = create(:completion_kit_metric)
    version = CompletionKit::MetricVersion.ensure_current_for(metric)
    create(:completion_kit_review, response: response_row, metric: metric, metric_version: version, ai_score: 4.0)

    get "/completion_kit/runs/#{run.id}/responses/#{response_row.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ck-source-chip")
    expect(response.body).to include(version.version_label)
  end
```

If `responses_spec.rb` already covers the show action, add only the `it` block, reusing its existing setup helpers where they fit. Confirm the route helper shape with `bundle exec rails routes -g responses` if the path above does not match.

- [ ] **Step 2: Run it**

Run: `bundle exec rspec spec/requests/completion_kit/responses_spec.rb -e "version chip"`
Expected: PASS, since the review resolves a real version.

- [ ] **Step 3: Update the Make current confirm copy**

In `app/views/completion_kit/metrics/show.html.erb:76`, replace the `turbo_confirm` string so it reflects in-place revert:

```ruby
                          data: { turbo_confirm: "Make #{v.version_label} the version to use? It becomes the version used in test runs, and the reviews you gave on it count again. Reviews on the version you're leaving stay with it." } %>
```

This is a view (filtered from coverage). The existing spec assertion that the page includes "Make current" still holds.

- [ ] **Step 4: Eyeball the dev page**

Boot the standalone server and open a response that has reviews (for example the page from the original report). Confirm the version chip now appears next to the scoring stars and the page does not error for any review.

Run: `cd standalone && DISABLE_SPRING=1 bin/rails s`

- [ ] **Step 5: Commit**

```bash
git add spec/requests/completion_kit/responses_spec.rb app/views/completion_kit/metrics/show.html.erb
git commit -m "Lock in the version chip on judgements and clarify the Make current confirm"
```

---

## Final verification

- [ ] Run the full suite: `bundle exec rspec`. Expected: green at 100 percent line and branch.
- [ ] Confirm `grep -rn "revert!" app lib spec` returns nothing.
- [ ] Confirm `standalone/db/schema.rb` shows the new foreign key on `completion_kit_reviews`.

---

## Self-Review

**Spec coverage:**
- Revert in place (web, API, MCP), remove `revert!`, drop the "logged as" copy, preserve legacy revert chips: Tasks 1, 2, 3. Legacy `source: "revert"` rows are untouched (no migration removes them) and the show view still renders the "Reverted" chip, so this holds with no extra task.
- Agreement stat and answer key correcting for free: no task needed; both are already scoped to the current version, and reverting in place makes the target current. Worth a sentence here so the implementer does not go looking for a change.
- Mandatory version: required association (Task 4), backfill (Task 5), foreign key (Task 6).
- Chip renders with no view change: Task 7.
- Factory ripple called out: Task 4, Step 4.

**Placeholder scan:** No TBD or vague steps. Every code step shows the code. The one judgement call left to the implementer (which specific specs break from the required association) is framed with the two concrete causes and how to fix each, not left open.

**Type and name consistency:** `publish!`, `ensure_current_for`, `metric_version`, `metric_version_id`, `source`, `version_label`, and `previously_current` are used consistently with the existing code read during planning. The foreign key is `on_delete: :nullify` everywhere it appears (Task 6 and the refinements note).
