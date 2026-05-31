# Calibration to Agreement Rename Design

**Goal:** Finish the user-facing rename started in 0.11.0 by renaming the "calibration" concept to "agreement" everywhere it appears: the model, the table, the services, the routes, the REST API resource, the MCP tools, the config flag, the CSS classes, the views, and the specs. This is a clean break with no aliases, shipped as 0.12.0.

**Scope note:** This is thread B, independent of the version-provenance work that shipped earlier. It is a pure rename with zero behavior change. The agreement signal itself (the `verdict` values agree, disagree, borderline) is unchanged.

---

## Background

In 0.11.0 the metric page's "Calibration" card was reframed to "Agreement," but the underlying model, table, REST API, MCP tools, config, CSS, and the response-page verdict-row link still say "calibration." This rename makes the whole stack consistent with the user-facing term. Because the REST API resource, the MCP tool names, and the config flag are externally visible, removing the old names is breaking; the gem is pre-1.0, so this ships as a 0.12.0 minor with a prominent CHANGELOG note, with no backward-compatibility aliases (clean break).

The word "calibration" does not overlap the verdict values (agree, disagree, borderline), so renaming the term cannot accidentally alter the signal values.

---

## Naming map

Every identifier below is renamed; the old name is removed.

| From | To |
| --- | --- |
| `CompletionKit::Calibration` model, `app/models/completion_kit/calibration.rb` | `CompletionKit::Agreement`, `agreement.rb` |
| Table `completion_kit_calibrations` | `completion_kit_agreements` |
| `CompletionKit::CalibrationMath`, `calibration_math.rb` | `CompletionKit::AgreementMath`, `agreement_math.rb` |
| `CompletionKit::MetricCalibrationStats`, `metric_calibration_stats.rb` | `CompletionKit::MetricAgreementStats`, `metric_agreement_stats.rb` |
| `CompletionKit::MetricCalibrationExamples`, `metric_calibration_examples.rb` | `CompletionKit::MetricAgreementExamples`, `metric_agreement_examples.rb` |
| `CompletionKit::CalibrationsController` (web), `calibrations_controller.rb` | `AgreementsController`, `agreements_controller.rb` |
| `CompletionKit::Api::V1::CalibrationsController`, `calibrations_controller.rb` | `Api::V1::AgreementsController`, `agreements_controller.rb` |
| `resources :calibrations` (3 route blocks) and `*_calibrations_path` helpers | `resources :agreements`, `*_agreements_path` |
| `app/views/completion_kit/calibrations/` (`_buttons`, `_trust_panel`, and others) | `app/views/completion_kit/agreements/` |
| `ck-calibration*` CSS classes (around 51 occurrences in `app/assets`) | `ck-agreement*` |
| Config `judge_calibration_enabled` (defined in `lib/completion_kit.rb`) | `judge_agreement_enabled` |
| MCP module `CompletionKit::McpTools::Calibrations`, `mcp_tools/calibrations.rb`, tools `calibrations_list` and `calibrations_create` | `McpTools::Agreements`, `agreements.rb`, `agreements_list`, `agreements_create` |
| `MetricVersion has_many :calibrations, dependent: :destroy` | `has_many :agreements, dependent: :destroy` |
| Factory `:completion_kit_calibration`, `spec/factories/calibrations.rb` | `:completion_kit_agreement`, `spec/factories/agreements.rb` |
| Around 172 "calibration" references across `spec/` | renamed |
| Local variables and partial-local names like `other_calibrations`, `calibration` | `other_agreements`, `agreement` |

The MCP `judges` tool that compares versions keeps its own tool name (it does not contain "calibration"); only its description ("calibration stats" becomes "agreement stats") and its use of `MetricAgreementStats` change.

---

## Clean break

These are removed, not aliased:

- The `/calibrations` routes (web and both API blocks). Only `/agreements` exists afterward.
- The MCP tools `calibrations_list` and `calibrations_create`. Only `agreements_list` and `agreements_create` exist.
- The `judge_calibration_enabled` config accessor. Only `judge_agreement_enabled` exists; there is no shim or deprecation warning.

A consumer still calling the old REST paths, old MCP tool names, or old config gets a normal not-found or no-method error, as expected for a flagged breaking release.

---

## Stays unchanged

- The `verdict` values `agree`, `disagree`, `borderline` (and the constant, renamed only by its host class to `Agreement::VERDICTS`).
- All columns on the renamed table: `verdict`, `created_by`, `corrected_score`, `note`, `excluded_from_examples`, plus the `run_id`, `response_id`, `metric_id`, `metric_version_id` references.
- All behavior. No method bodies change except where they reference a renamed constant, class, table, route helper, or config accessor.

---

## Table migration

`rename_table :completion_kit_calibrations, :completion_kit_agreements`, which preserves every existing row (the standalone database holds real agreement data). Index names are renamed for cleanliness (`index_ck_calibrations_*` to `index_ck_agreements_*`), and the foreign keys to runs, responses, metrics, and metric_versions carry over to the renamed table. Applied in:

- a new engine migration,
- its installed standalone copy (`bin/rails completion_kit:install:migrations`, then `db:migrate`),
- the regenerated `standalone/db/schema.rb`,
- the inline test schema in `spec/rails_helper.rb` (the `create_table` name and its index names).

Verification: the agreement row count in the standalone database is identical before and after the migration.

---

## Verdict-row link and anchor

In the response-page verdict row (the partial that moves to `agreements/_buttons.html.erb`), the `metric_path(metric)` link is relabeled from "Calibration ->" to "Agreement ->" and pointed at the Agreement card via an anchor (`metric_path(metric, anchor: "agreement")`). The Agreement card is the trust-panel partial (moving to `agreements/_trust_panel.html.erb`); its root container gets `id="agreement"` as the anchor target.

---

## Execution approach

Staged by layer, with the suite green between each stage, rather than one global sweep, so each step is reviewable and the spec renames land incrementally:

1. Model and table (model rename, association rename, the `rename_table` migration plus schemas, the factory).
2. Services (`AgreementMath`, `MetricAgreementStats`, `MetricAgreementExamples`) and their callers.
3. Controllers and routes (web and API), path helpers, and the views directory move.
4. Views and CSS (`ck-agreement*`), including the verdict-row link relabel and anchor.
5. MCP tools and the config flag.
6. A final sweep of remaining spec references and a grep to confirm no "calibration" remains.

Coverage note: `db/`, `app/views/`, and `app/assets/` are excluded from SimpleCov, so the table migration, view moves, and CSS renames are verified behaviorally. The Ruby renames (model, services, controllers, MCP, config) keep 100 percent line and branch coverage through their renamed specs.

---

## Version and release

Ships as 0.12.0. The CHANGELOG entry flags the break: renamed the Calibration model and `completion_kit_calibrations` table to Agreement; removed the `/calibrations` routes, the `calibrations_*` MCP tools, and the `judge_calibration_enabled` config in favor of `/agreements`, `agreements_*`, and `judge_agreement_enabled`. Both lockfiles (engine root and `standalone/`) are bumped, per the release process.

---

## Testing

- Full suite green at 100 percent line and branch after the rename, with the roughly 172 spec references and the inline schema table name updated.
- The standalone `rename_table` preserves the agreement row count (verified before and after).
- A final `grep -rin "calibration" app lib config db spec` returns nothing (the verdict values do not contain the word, so zero remnants is the expected result).

---

## Out of scope

- Any behavior change to the agreement feature.
- Renaming the `verdict` values or the agreement-stat method names (`agreement_point`, `borderline_rate`), which do not contain "calibration".
- Backward-compatibility aliases for the removed routes, tools, or config.
