# Metric Version Provenance Design

**Goal:** Make a metric's version provenance honest and visible: reverting returns to the existing version (with its reviews and signal intact) instead of minting a copy, and every scored judgement reliably resolves the metric version the judge used.

**Scope note:** This is part A of a two-part effort. Part B, the full Calibration to Agreement rename (model, table, routes, REST API, MCP tools, config, plus the verdict-row link relabel and anchor), is a breaking change and is deferred to its own brainstorm and spec. It is out of scope here.

---

## Background

Two related gaps came out of the 0.11.0 review.

**Revert mints a new version.** `MetricVersion#revert!` creates a fresh version that copies the target version's content, marks it current (`source: "revert"`), and leaves the target's calibrations behind. Two consequences:

- The signal does not carry. Calibrations belong to a specific `metric_version_id`, so the new version starts with zero agreement and an empty validated-improvements answer key, even though its content is identical to the target.
- The provenance is lost. The new version records `source: "revert"` but not which version it re-applies.

**Judgements can point at deleted versions.** `Review belongs_to :metric_version, optional: true`. `judge_review_job` stamps `ensure_current_for(metric).id` on every successful score, but there is no database guarantee that the referenced version still exists. In the current development database all 285 reviews carry a `metric_version_id` that resolves to nothing (the version table was reset at some point; reviews still reference the old ids). The response page hides the version chip whenever `review.metric_version` fails to resolve, so the chip silently disappears.

---

## Part 1: Revert in place

Reverting becomes "make the existing version current again" rather than "mint a copy."

**Behavior.** `publish!` already sets the target current, clears `current` on the others, and copies the target's instruction and rubric onto the metric. That is exactly an in-place revert. So the reverting path calls `version.publish!` instead of `version.revert!`. No new version is created. The version pointer becomes non-monotonic by design: after running v3 and v4, reverting to v2 simply makes v2 current again, and the versions table shows v2 as published with v3 and v4 sitting above it.

**Why the gaps close.** The reverted-to version is current again with its own calibrations attached, so `MetricCalibrationStats` and `MetricImprovementValidator`, both scoped to the current version, reflect it immediately with no change to those services. Provenance is self-evident from the table: v2 is the published version again.

**Call sites.** Three callers branch on `published? && !current?`:

- `MetricsController#publish_draft` (web)
- `Api::V1::MetricVersionsController#publish`
- `McpTools::MetricVersions.publish`

All three drop the revert branch and call `version.publish!`, then return the now-current version (the target itself). The web action keeps a conditional only to choose the flash copy. `MetricVersion#revert!` is removed.

**Copy.** Drop the "logged as vN" framing.

- Revert notice (web): "{Metric} is back on {target}. Its reviews count again; the ones you gave on {previous current} stay with that version."
- The "Make current" confirm dialog on a past published version gets the same clarification: making it current brings its own reviews back into the agreement signal, and reviews on the version being left stay with that version.

**Legacy data.** Existing versions with `source: "revert"` remain as valid historical rows and still render the "Reverted" source chip. No new revert-source versions are created. The `source` value is retained for display compatibility.

**Edge cases.**

- Publishing a draft is unchanged; it still calls `publish!` in place.
- Calling `publish!` on the version that is already current is a harmless no-op. The web UI only offers "Make current" on non-current versions; the API and MCP tolerate it.
- `published_at` is preserved on re-publish (`publish!` keeps the existing value), so the table's created/published timestamps and ordering by version number are unchanged.

---

## Part 2: Mandatory version on judgements

Guarantee that every scored judgement references a version that exists, so the chip always renders.

**Model.** Drop `optional: true` from `belongs_to :metric_version` on `Review`. The association then validates that the version exists on any validated save. The success path in `judge_review_job` already assigns it, so succeeded reviews satisfy the rule.

**Database.** Add a foreign key on `completion_kit_reviews.metric_version_id` referencing `completion_kit_metric_versions`, `on_delete: :restrict`. Restrict is safe: the application only ever destroys draft versions, which never have reviews, so this never blocks a legitimate delete; it only prevents orphaning a reviewed version.

The column stays nullable rather than NOT NULL. NOT NULL would fight three real cases: the `before_perform` placeholder row (status retrying), the `record_terminal_failure` row, and judging a metric that was deleted between enqueue and run (no version can be assigned). Those rows never show a chip because they have no score. A required association plus the foreign key plus always stamping on success delivers the user-visible guarantee (every scored judgement resolves its version) without the NOT NULL friction. A null `metric_version_id` is not checked by the foreign key, so failure and placeholder rows remain valid.

**Stamping.** Keep the success-path stamp (`metric_version_id: ensure_current_for(metric).id`). Also stamp it in `before_perform` and `record_terminal_failure` when the metric still exists, so failure and retry rows carry a version where one is available. When the metric is gone, leave it null.

**Backfill (runs before the foreign key).** For every review whose `metric_version_id` is null or does not reference an existing version, and whose metric still exists, re-point it to that metric's current version, calling `ensure_current_for` first for metrics that have no version. Reviews whose metric is also gone are left null. After this, no non-null `metric_version_id` dangles, so the foreign key can be added. In the current dev database this re-points all 285 reviews and creates a current version for the six metrics that have none. The re-pointed label reflects the metric's current version rather than the lost original, an accepted small fiction for already-orphaned historical rows.

**Chip.** No view change. The existing chip in `responses/show.html.erb` renders as soon as `review.metric_version` resolves. It stays beside the scoring stars (the earlier idea to move it next to the metric name is dropped).

**Ripple to consider in the plan.** Dropping `optional: true` means any validated save of a review without a version now fails. The review factory and any spec or flow that builds a review through validations must associate a metric version (a factory default association or trait). The plan must update these so the suite stays green at 100 percent coverage.

---

## Affected surfaces

- `app/models/completion_kit/metric_version.rb` (remove `revert!`)
- `app/models/completion_kit/review.rb` (required association)
- `app/jobs/completion_kit/judge_review_job.rb` (stamp in placeholder and failure paths)
- `app/controllers/completion_kit/metrics_controller.rb` (`publish_draft` in-place + copy)
- `app/controllers/completion_kit/api/v1/metric_versions_controller.rb` (`publish` in-place)
- `app/services/completion_kit/mcp_tools/metric_versions.rb` (`publish` in-place)
- `app/views/completion_kit/metrics/show.html.erb` (confirm dialog copy on "Make current")
- Two migrations: the data backfill, then the foreign key
- `db/schema.rb` in standalone, the engine migration plus its installed copy, and the inline schema in `spec/rails_helper.rb`
- Review factory and affected specs

## Testing

- Revert in place: reverting to a past published version makes it current, creates no new version, leaves the abandoned version's reviews tied to it, and brings the target's calibrations back into the agreement signal. Same for the API and MCP publish paths returning the target version.
- Removal of `revert!`: existing revert specs are rewritten to the in-place behavior; no spec references `revert!`.
- Mandatory version: a validated review save without a version fails; the success path stamps the current version; the foreign key blocks deleting a version that has reviews; the backfill re-points dangling reviews and creates versions for version-less metrics.
- Chip: a review whose version resolves renders the chip; a failure or placeholder review with a null version renders no chip and does not error.
- Maintain 100 percent line and branch coverage.

## Out of scope

- Part B: the Calibration to Agreement rename across model, table, routes, REST API, MCP tools, config, CSS classes, and remaining visible text, including relabeling the verdict-row link and anchoring it to the agreement card. Its own brainstorm, spec, deprecation strategy, and release.
- Moving the version chip next to the metric name.
- Backfilling a true historical version for already-orphaned reviews (the original versions are gone).
