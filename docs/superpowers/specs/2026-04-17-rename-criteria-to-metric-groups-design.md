# Rename Criteria → Metric Group — design

## Goal

Rename the `Criteria` concept to `Metric Group` across the entire product: database schema, Ruby classes, URL paths, REST API, MCP tools, views, tests, seeds, and documentation. Clean cutover with no backwards-compatibility aliases. Data preserved in place.

## Why

The word "criteria" is technically correct (the plural of "criterion") but confusing in product use. It doesn't describe what the entity IS when a new user encounters it. "Metric group" is self-describing: it's a group of metrics. The UI can use "group metrics" as a natural verb phrase ("Group metrics for reuse across runs").

Full rename rather than surface-only because this is pre-release (`0.1.0.rc1` on RubyGems with effectively no downstream users). Internal names matching external names avoids the confusion of `CompletionKit::Criteria` in code vs. "Metric Group" in the UI.

## Scope — what renames

### Names

| Thing | Before | After |
|---|---|---|
| Model class | `CompletionKit::Criteria` | `CompletionKit::MetricGroup` |
| Join model | `CompletionKit::CriteriaMembership` | `CompletionKit::MetricGroupMembership` |
| Primary table | `completion_kit_criteria` | `completion_kit_metric_groups` |
| Join table | `completion_kit_criteria_memberships` | `completion_kit_metric_group_memberships` |
| FK column in join | `criteria_id` | `metric_group_id` |
| Web controller | `CriteriaController` | `MetricGroupsController` |
| API controller | `Api::V1::CriteriaController` | `Api::V1::MetricGroupsController` |
| Web route | `/completion_kit/criteria` | `/completion_kit/metric_groups` |
| REST API path | `/api/v1/criteria` | `/api/v1/metric_groups` |
| MCP tools | `criteria_list`, `_get`, `_create`, `_update`, `_delete` | `metric_groups_list`, `metric_groups_get`, etc. |
| Factory trait | `:completion_kit_criteria` | `:completion_kit_metric_group` |
| UI label | "Criteria" / "criteria" | "Metric group" / "metric groups" |
| UI verb | (various) | "Group metrics for reuse" |
| Inflection rule | `inflect.irregular "criterion", "criteria"` | removed (no longer needed) |

### Files moved

- `app/models/completion_kit/criteria.rb` → `metric_group.rb`
- `app/models/completion_kit/criteria_membership.rb` → `metric_group_membership.rb`
- `app/controllers/completion_kit/criteria_controller.rb` → `metric_groups_controller.rb`
- `app/controllers/completion_kit/api/v1/criteria_controller.rb` → `metric_groups_controller.rb`
- `app/views/completion_kit/criteria/` → `app/views/completion_kit/metric_groups/` (directory)
- `app/services/completion_kit/mcp_tools/criteria.rb` → `metric_groups.rb`
- `spec/models/completion_kit/criteria_spec.rb` → `metric_group_spec.rb`
- `spec/requests/completion_kit/criteria_spec.rb` → `metric_groups_spec.rb`
- `spec/requests/completion_kit/api/criteria_spec.rb` → `metric_groups_spec.rb` (if it exists)
- `spec/factories/criteria.rb` → `metric_groups.rb`
- `spec/factories/criteria_memberships.rb` → `metric_group_memberships.rb`
- `spec/services/completion_kit/mcp_tools/criteria_spec.rb` → `metric_groups_spec.rb`

### In-place edits

- `app/models/completion_kit/metric.rb` — update associations (`has_many :criteria_memberships` → `metric_group_memberships`; `has_many :criterias, through: :criteria_memberships, source: :criteria` → `metric_groups, through: :metric_group_memberships, source: :metric_group`)
- `config/routes.rb` — change both web and API resources declarations
- `app/services/completion_kit/mcp_dispatcher.rb` — update tool name routing
- `app/helpers/completion_kit/application_helper.rb` — any `criterion_path` / `criteria_path` references
- `app/views/**` — every `link_to`, path helper, and label string referring to Criteria, including the layout nav/breadcrumbs across all pages
- `app/views/completion_kit/metrics/index.html.erb` — the "Bundle them into a criteria →" hint → "Group them into a metric group →"
- `app/views/completion_kit/api_reference/index.html.erb` — endpoint docs, curl examples, MCP tool snippets
- `lib/completion_kit/engine.rb` — remove `inflect.irregular "criterion", "criteria"`
- `standalone/db/seeds.rb` — `CompletionKit::Criteria` / `CompletionKit::CriteriaMembership` references
- `spec/rails_helper.rb` — `create_table` schema and FK column name in the in-memory test schema
- `README.md` — the Criteria concept bullet and any other mentions
- `CHANGELOG.md` — new `[Unreleased]` entry documenting the breaking rename
- `CONTRIBUTING.md` — check for mentions
- Memory files referencing Criteria — update to reflect new names (live memory, not historical docs)

### Historical documents — NOT edited

- `docs/superpowers/specs/2026-04-14-launch-design.md`
- `docs/superpowers/plans/2026-04-14-launch.md`
- Any existing completed design/plan docs

These are time-stamped snapshots. Leave them alone.

## Database migration

Single migration, reversible, data-preserving. Run in both engine (`db/migrate/`) and installed into standalone via `completion_kit:install:migrations` before committing.

```ruby
class RenameCriteriaToMetricGroups < ActiveRecord::Migration[8.1]
  def change
    rename_table :completion_kit_criteria, :completion_kit_metric_groups
    rename_table :completion_kit_criteria_memberships, :completion_kit_metric_group_memberships
    rename_column :completion_kit_metric_group_memberships, :criteria_id, :metric_group_id
  end
end
```

**Postgres behavior:**
- `rename_table` preserves all data, constraints, indexes, and RLS state
- Primary keys and timestamps survive untouched
- Index names may not auto-rename; add explicit `rename_index` calls if Postgres keeps the old index names with the new table (verify post-deploy via `\d+` on the renamed tables). Minor cosmetic; not a correctness issue.

**Production impact:**
- Supabase currently has 1 row in `completion_kit_criteria` and 3 rows in `completion_kit_criteria_memberships`
- After migration: same row counts, renamed tables, same foreign key relationships
- No data loss, no re-seeding needed

## Deployment

Single commit, single push, one deploy.

1. All code renames + file moves in the working tree
2. Engine migration file at `db/migrate/<timestamp>_rename_criteria_to_metric_groups.rb`
3. Run `cd standalone && bin/rails completion_kit:install:migrations` to copy the migration into `standalone/db/migrate/` (so Render's pre-deploy sees it)
4. Commit: `rename Criteria to MetricGroup (breaking)`
5. Push to `origin/main`
6. CI runs. Must stay 100% line and branch coverage, all specs pass
7. Render auto-deploys (or manually trigger if the auto-deploy bug we hit earlier recurs). Pre-deploy runs `bin/rails db:migrate` which executes the rename against Supabase
8. Post-deploy verification:
   - Query Supabase via `mcp__supabase__list_tables`. Confirm `completion_kit_metric_groups` and `completion_kit_metric_group_memberships` exist with 1 and 3 rows respectively. Confirm `completion_kit_criteria*` do not exist.
   - Run `mcp__supabase__get_advisors(type: security)`. Confirm no new `rls_disabled_in_public` ERROR (per deployment-topology foot-gun).
   - Load the standalone app's Metrics and Metric Groups pages in a browser. Confirm the UI renders with new names.

**No downtime expected.** Rails' default deploy model (old Puma serves old code until new Puma is ready) handles the brief moment of code/schema skew.

## Rollback

Migration is fully reversible (`rename_table` back, `rename_column` back). Two options:

1. `git revert <commit>` on `main`, push. Render deploys the revert, pre-deploy runs the down migration, everything goes back to `Criteria`.
2. Manually run `bin/rails db:rollback` in the Render shell if the code deploy succeeded but something runtime is broken. Then revert the code commit.

Option 1 is more systematic. Option 2 is faster if the problem is runtime-only.

## Breaking change announcement

- `CHANGELOG.md` under `[Unreleased]` with a `### Changed` section: "**Breaking:** Criteria renamed to Metric Groups. REST API paths `/api/v1/criteria` → `/api/v1/metric_groups`. MCP tools `criteria_*` → `metric_groups_*`. Ruby class `CompletionKit::Criteria` → `CompletionKit::MetricGroup`. No backwards-compatibility aliases."
- When `0.2.0` ships, this becomes the release notes header. Any downstream consumer of `0.1.0.rc1` who upgrades must update their API calls and class references.

## Verification

- `grep -rn "Criteria\|criteria\|CriteriaMembership\|criteria_memberships\|criterion_path\|criteria_path" app/ lib/ spec/ standalone/db/seeds.rb standalone/app/ site/ README.md CHANGELOG.md CONTRIBUTING.md` returns zero matches (ignoring the launch spec and plan, and the generic English use of "criteria" in the landing page comparison table if any remains)
- Full test suite passes: 448+ specs, 100% line and branch coverage
- Application boots in development (`cd standalone && bin/rails s`)
- Supabase post-deploy verification passes (row counts, advisor check)
- `/completion_kit/metric_groups` returns 200 with proper content
- `/completion_kit/criteria` returns 404 (old path is gone, no redirect)
- `/api/v1/metric_groups` with a valid bearer token returns the expected JSON
- `/api/v1/criteria` returns 404

## Out of scope

- Adding new fields or behavior to Metric Group — this is a pure rename
- Adding a JSON migration for downstream API consumers — they just need to update their code
- UI redesign of the metric groups page beyond the label changes — the layout change in `b492c0a` / `f829df7` stays
- Landing page changes — landing page uses "criteria" in generic English ("criteria you define") which is correct English and does NOT refer to the Criteria entity

## Open questions

None. Design is complete.
