# Changelog

All notable changes to CompletionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Run-history retention is now an engine-wide seam.** The 0.16.3 `runs_index_scope` / `runs_index_footer_partial` hooks are replaced by `runs_display_scope` / `runs_display_footer_partial`. The scope is honored everywhere the engine lists or counts runs (runs index, prompt and dataset show pages, compare picker, new-run tag defaults, v1 API index and its `X-Total-Count`, MCP `runs_list`, API reference recent-runs, provider-credential stats) and across child records that traverse runs (trust-panel sample, agreement examples on a metric page) via `Run.display_scoped` and `Run.visible_run_ids`. The footer partial now renders below the runs list on the index and the prompt and dataset show pages. Id-addressed lookups, delete-cascade counts, the auto-name counter, and judge few-shot seeding deliberately still see every run.

## [0.16.3] - 2026-06-24

### Added
- **Host integration hooks for the runs list (`runs_index_scope`, `runs_index_footer_partial`).** A host app can now filter the runs index and append its own footer to the list through supported config seams, instead of reaching into the controller or overriding the view. `config.runs_index_scope` takes a callable evaluated against the index relation, so a multi-tenant host can apply something like run-history retention to the list only, rather than a global `default_scope` that would null `Run` associations everywhere else. `config.runs_index_footer_partial` names a partial rendered below the list, for an "older runs are hidden, upgrade to see them" notice; it receives the shown runs as a `runs` local. Both default to off, so standalone behaviour is unchanged.

## [0.16.2] - 2026-06-12

### Changed
- **Require Ruby >= 3.2.0.** The gemspec claimed `>= 3.1.0`, but the dependencies (Rails 7+, bundler, and net-imap 0.6+) already require Ruby 3.2. Correcting the floor also unblocks the root Dependabot security-update job, which resolves against the declared minimum and was failing because the net-imap/puma patches need Ruby 3.2.

## [0.16.1] - 2026-06-12

### Fixed
- **`runs_generate` no longer returns an error for a run that already started (#68).** On a host that remounts the engine under a parameterized scope (such as `/orgs/:org_slug`), `Run#start!` raised `UrlGenerationError` from `warm_routes!` after the row jobs were already enqueued, so an MCP-driven agent saw a failure for a run that was in fact running and could retry into a double-generate. `warm_routes!` now survives parameterized mounts (the route set finalizes before the throwaway helper call), and `start!` treats its UI broadcasts as best-effort so a broadcast failure can never turn a started run into an API error.

## [0.16.0] - 2026-06-12

### Added
- **Validated prompt suggestions, with a gated publish (#67).** A prompt-improvement suggestion now re-runs the candidate prompt against a held-out slice of the run's reviewed responses (capped at 30), re-judges each one, and shows a before/after scoreboard (improved, held, regressed) before you publish. One-click apply is gated: a rewrite that scored net-negative, or that could not be re-scored, asks for confirmation first. The MCP `prompts_suggest_improvement` tool returns the same measured delta plus a `net_negative` flag.

### Changed
- **The judge no longer grades against the prompt outside a metric's scope (#66).** The judge used to receive the full prompt instruction text on every review, so a rule a prompt added (a banned-word list, a length limit) could move scores for metrics whose stated scope said nothing about it, and could corrupt version-to-version comparison. The judge now keeps the prompt only as scoped reference: it weighs the prompt for adherence dimensions (instruction-following, format or schema, tone or persona) and judges intrinsic-quality dimensions (correctness, conciseness) on the output alone. Held-out validation for both metric and prompt suggestions inherits the same scoping. Scores for output-quality metrics may shift as the prompt stops biasing them.
- **Provider-neutral defaults — the engine no longer assumes OpenAI (#65).** `CompletionKit.config.judge_model` now defaults to `nil` (was `"gpt-4.1"`) and accepts a callable, so a multi-tenant host can inject a per-org default the way `tenant_scope` already does. When no judge model is supplied, the judge and metric-suggestion paths resolve an available judging model from the registry instead of falling back to OpenAI; if none can be resolved they raise a clear `ConfigurationError` rather than silently calling OpenAI. The onboarding sample prompt now picks an available generation model (and is skipped when none exists) instead of hardcoding `gpt-4o-mini`, and provider inference no longer forces a `gpt-`/`claude-` id onto a provider that isn't configured. Hosts that relied on the implicit `gpt-4.1` default should set `config.judge_model` explicitly.

## [0.15.1] - 2026-06-09

### Fixed
- **Anthropic capability probe no longer mis-flags thinking-by-default models as unusable for judging.** `extract_text` read `content[0].text`, but newer Claude models (e.g. `claude-fable-5`) emit a `thinking` content block before the answer on the more involved judge prompt, so `content[0]` was the thinking block, the probe saw empty text, and judging was marked unsupported. It now finds the `text` block past any leading thinking block, matching how the OpenAI path already skips reasoning items. (A normal refresh re-probes affected models, so they recover without a reset.)

## [0.15.0] - 2026-06-09

### Changed
- **MCP `prompts_update` no longer auto-publishes a revision (#58).** Updating a prompt that already has runs now creates the new version as a DRAFT (`current=false`) and leaves promotion to `prompts_publish`, matching the draft-then-publish model used for metric versions. Agent-driven flows get a review gate instead of shipping every edit straight to current. (Prompts with no runs are still updated in place.)

### Fixed
- **Refresh on the provider edit page now shows live progress (#63).** `ckStartDiscoveryPolling` bailed when the page had no `#discovery_status_` element — exactly the completed-state edit page where you click Refresh — so the icon never spun and no progress appeared. Polling now gates on the statuses URL instead, so the edit-page refresh starts polling and the card morphs into the discovering state.

## [0.14.0] - 2026-06-08

### Added
- **CSV file upload for datasets over the REST API.** `POST /api/v1/datasets` and `PATCH /api/v1/datasets/:id` now accept a multipart `file` field as an alternative to an inline `csv_data` string, so a CLI/SDK/UI can upload a CSV file directly instead of embedding it in the request body.
- **New MCP tool `datasets_create_from_url`.** Creates a dataset by downloading CSV from a public http(s) URL server-side, so large datasets no longer have to pass through the tool-call arguments (which an LLM client otherwise has to emit token-by-token). The URL is SSRF-checked and the download is capped at 10MB.

## [0.13.0] - 2026-06-08

### Changed (breaking)
- **Renamed the MCP tool `judges_suggest` to `metrics_suggest_variants`.** It rewrites a metric's judge instruction into draft variants, so it now lives in the metrics namespace next to the REST `metrics#suggest_variants`. No alias is kept — update MCP callers (clients that discover tools via `tools/list` pick up the new name automatically).

### Added
- **New MCP tool `prompts_suggest_improvement`.** Suggests an improved prompt template grounded in a run's test results and judge feedback (the same engine behind the web "Suggest improvements"): it returns the reasoning and rewritten template and persists a `Suggestion`. Takes a `run_id` and rejects judge-only runs that have no prompt.

## [0.12.4] - 2026-06-08

### Fixed
- **The MCP server now runs statelessly, so clients no longer get disconnected.** Previously every non-`initialize` request had to present a live `Mcp-Session-Id`; once a session passed its idle TTL, the next call was rejected with `-32000 "Session not initialized"` and the client had to reconnect. Per the Streamable HTTP transport spec, the server now serves `tools/call` and other operations without requiring a prior `initialize` or a valid session id. `initialize` still mints and returns an `Mcp-Session-Id` for clients that use one, and `DELETE` still tears a session down.

## [0.12.3] - 2026-06-08

### Fixed
- **The "Refresh models" button on the prompt and run forms now works when the engine is mounted under a non-default path.** Like the discovery poll fixed in 0.12.2, the button's `refresh_models` POST was hardcoded to the standalone mount, so it 404'd on hosts that remount the engine (such as a per-tenant Cloud scope) and never started discovery. The button URL and the live-progress poll URL are now rendered from their route helpers into `data-*` attributes, so both follow whatever mount the host uses.

## [0.12.2] - 2026-06-08

### Fixed
- **Live model-discovery polling now works when the engine is mounted under a non-default path.** The polling request added in 0.12.1 hardcoded the engine's standalone mount (`/completion_kit/provider_credentials/statuses`), so a host that remounts the engine elsewhere (for example under a per-tenant URL scope) polled a path that 404s, and the providers page never updated. The poll URL is now rendered server-side from the `statuses` route helper into a `data-ck-statuses-url` attribute, so it follows whatever mount the host uses. The one remaining unguarded broadcast, `broadcast_model_dropdowns`, is now wrapped too, so a worker render failure logs and continues instead of aborting discovery completion.

## [0.12.1] - 2026-06-08

### Fixed
- **Model discovery no longer marks capable Claude models as unable to generate.** The capability probe sent `max_tokens: 65536`, which exceeds several Anthropic models' output caps (Haiku 4.5 and Sonnet-class models cap at 64000; Opus 4 / 4.1 at 32000) and returned a 400 — silently flagging those models as generation-incapable. The probe budget is now provider-aware: the large ceiling stays only for OpenAI reasoning models, while Anthropic and Ollama probe within model limits.
- **Refreshing models now re-checks previously failed ones.** A non-retryable 4xx on the generation probe was cached as a permanent incapability that nothing could clear, so a model broken by a transient or since-fixed error stayed dead even on Refresh. The Refresh action now forces a re-probe of failed-generation models (resetting them to unknown) while leaving confirmed-good models untouched.
- **Provider model-discovery progress updates live again.** Turbo broadcasts that rendered controller partials from the background worker could silently fail to publish, leaving the providers page with no discovery animation or progress. Live updates are now driven from a polled `statuses` endpoint rendered in request context, and worker broadcasts log-and-continue instead of risking the discovery job.

## [0.12.0] - 2026-05-31

### Changed (breaking)
- Renamed the "calibration" concept to "agreement" throughout. The `Calibration` model and `completion_kit_calibrations` table are now `Agreement` / `completion_kit_agreements`. The REST API resource is now `/agreements` (was `/calibrations`), the MCP tools are `agreements_list` / `agreements_create` (were `calibrations_*`), and the config flag is `judge_agreement_enabled` (was `judge_calibration_enabled`). No aliases are kept; update API and MCP callers accordingly.

### Added
- **Every judgement records the metric version it was scored under.** `Review` now requires a metric version, backed by a foreign key that nullifies on delete; reviews that pointed at deleted versions were backfilled to their metric's current version. The response page shows a version chip beside each judge score, with a `vN → vN` marker when the metric has moved on since the score was given.

### Changed
- **Reverting a metric version now happens in place.** Reverting to an older published version republishes that version instead of minting a copy, so the agreement signal and the validated-improvements answer key tied to it come back with it. `MetricVersion#revert!` is gone; the web, REST API, and MCP publish paths all revert in place.

## [0.11.0] - 2026-05-31

### Added

- **Validated metric improvements.** When you ask the model to improve a metric, the suggested change is re-scored against the cases you have already reviewed and shown as a before/after scoreboard before you publish: how many of your reviews the candidate now matches, with a Fixes / Keeps / Breaks breakdown. "Breaks" (agreements the candidate would regress) is the honest, semi-held-out signal, since the candidate is generated from your disagreements. Publishing a net-negative candidate warns. The flow runs in a background job (`MetricSuggestionJob`) with a Turbo-streamed pending state, retries on transient LLM errors, and a failure state so a click never strands on a spinner. The candidate is validated against the current version's reviewed cases (the 30 most recent), and the result is stored on the draft as `validation_summary`.

### Changed

- **"Calibration" is reframed as "Agreement"** across the metric page. The card, the one-line description, the measured-state stat ("Agrees with you ~X% of N reviews"), and the version source chip ("AI suggestion") drop the ML jargon for plain language: how often the judge lands on the same score you would.
- **Suggest improvements runs asynchronously.** Instead of blocking the request on the model, it enqueues the job and shows a pending state that resolves in place over Turbo. Triggered from the edit page, it now lands you on the metric page where the comparison appears.

## [0.10.0] - 2026-05-30

### Added

- **Review-grounded judging.** A new opt-in `judge_examples_from_reviews` config flag (off by default, meaningful only when `judge_calibration_enabled`) lets the judge see recent human corrections while it scores. When a reviewer disagrees with a score, that corrected case is harvested automatically (no pinning) and shown to the judge as a worked example on the next run, closing the loop from reviewing misses to better scoring. Examples are scoped to the metric's current published version with no fallback to superseded versions, never include the response being scored, drop cases that have no judge score, and are capped at five. The metric show page surfaces the active cases under "Guiding the judge", each linking to its review, with a per-case mute. The plumbing reuses the prompt-injection slot 0.9.0 removed, sourced from reviews rather than a hand-pinned set.
- **Published-version column on the metrics table**, styled like the prompts table and defaulting to v1.

### Changed

- **The metric versions table now matches the prompts version table.** The version cell shows the label, a plain Published chip, and a small inline Δ that opens the diff modal; the separate "Δ Change" column and the bespoke version-state / magnitude styling are gone. Columns spread evenly instead of bunching to the left.
- **Suggest improvements** moved into the calibration card header (top-right beside the kicker), consistent with where it sits on the prompt card.
- **The stale-version notice on a review** is now a concise `vN → vN` chip with a tooltip, replacing the full-width amber paragraph and the colored left border.
- **The not-measured calibration hint** names the version it is measuring ("v2 needs 10 human reviews of the judge's scores"), and reviews carried over from an earlier version are noted in a quieter line beneath it.

### Fixed

- **Calibration "review a score" links only target the current version.** "Review a judge's score" and "Review another score" now point at a response scored against the metric's current published version, so they no longer drop you onto a superseded-version review.

## [0.9.0] - 2026-05-30

### Changed

- **Metric page overhaul.** Calibration moved off the index table into its own card on the metric show page: a one-line plain-language description, a mono labeled stat strip (Agreement / Margin / Read / Sample / Unclear with visible labels instead of tooltip-only tokens), and a sparkles "Suggest improvements" button. The card sits below a redesigned Versions table with a "Δ Change" column that summarizes each version's delta from its predecessor as a Trivial / Minor / Major text link opening a side-by-side diff modal. Drafts carry an inline Publish button and a trash-icon Discard (also in the diff modal); the modal closes the loop with Publish / Edit / Discard in its footer. After "Suggest improvements" generates a draft, the metric page opens straight onto that draft's diff modal.
- **Metric vs. judge terminology.** Publishing changes the metric's current version, not "the judge" (the judge is the model that grades). Reworded the publish / revert / stale-version / re-grade copy across the metric show page, the response review cards, the run show page ("current metrics", not "current judge"), the flashes, and the `metric_versions` MCP tool description. Calibration verdicts are surfaced as "human reviews".
- **Version-change classification** lives on `MetricVersion#change_summary_against(previous)` (magnitude + label), routed through `Metric.normalize_rubric_bands` so it matches the displayed rubric and tolerates odd stored band shapes.

### Removed

- **BREAKING: few-shot pinning ("Remember this" / "Cases to learn from") is gone.** The calibration loop is now just measure (human reviews → trust signal) and fix (disagreements → "Suggest improvements" rewrites the instruction and rubric into a new version). The separate manual lever for pinning individual disagreements as in-context judge examples overlapped with the rubric-rewrite path and read as busy-work. Removed: the `POST /api/v1/metrics/:id/add_few_shot` and `DELETE /api/v1/metrics/:id/remove_few_shot` endpoints, the matching web routes/actions, the "Cases to learn from" section on the metric show page, the few-shot injection into the judge prompt (`human_examples`), the "Pinned cases" section of the improve-the-metric meta-prompt, and the `completion_kit_metrics.few_shot_examples` column (dropped by migration — any pinned-example data is discarded on upgrade). Disagreements still drive the trust signal and still feed "Suggest improvements".

## [0.8.0] - 2026-05-29

### Changed

- **BREAKING: REST API error responses now use one canonical shape.** Every error carries a top-level `error` string. Validation failures (422) additionally include a `details` object keyed by field (`{ "error": "Validation failed", "details": { "name": ["can't be blank"] } }`). Previously three shapes were in play: `{error: "..."}` for business-rule and auth errors, `{errors: {field: [...]}}` for ActiveModel validation, and `{errors: ["..."]}` for run start/rerun failures. Clients reading `errors` must move to `error` (single message) or `details` (field map). Centralized in `render_error` / `render_validation_errors` helpers on `Api::V1::BaseController`.

## [0.7.0] - 2026-05-28

### Added

- **REST API parity with MCP and the web UI** for the 0.5.43 / 0.6.0 feature work. New endpoints: `GET/POST/POST(:id/publish)/DELETE /api/v1/metrics/:metric_id/metric_versions`, `POST /api/v1/runs/:id/rerun`, `POST /api/v1/runs/:id/regrade`, `GET /api/v1/runs/:id/compare?with=:other_id`, `POST /api/v1/runs/:id/retry_failures`, `POST /api/v1/metrics/:id/suggest_variants`, `POST /api/v1/metrics/:id/add_few_shot`, `DELETE /api/v1/metrics/:id/remove_few_shot`.
- **Flat calibrations endpoint:** `GET /api/v1/calibrations` with `run_id`, `response_id`, `metric_id`, `metric_version_id`, `created_by`, `verdict` filters. `DELETE /api/v1/calibrations/:id` for unwinding a mis-cast verdict. Nested `POST /api/v1/runs/:run_id/responses/:response_id/metrics/:metric_id/calibrations` unchanged.
- **Pagination on every index endpoint:** `?limit=` (default 50, max 500), `?offset=` (default 0), `X-Total-Count` / `X-Limit` / `X-Offset` response headers. Resource-specific filters: runs `?status=`, `?prompt_id=`, `?dataset_id=`; responses `?status=`; prompts / runs / metrics / datasets / metric_groups `?tag[]=` with OR semantics. Shared `paginate` and `filter_by_tags` helpers on `Api::V1::BaseController`.
- **MCP tools for MetricVersion management:** `metric_versions_list`, `metric_versions_publish`, `metric_versions_dismiss`. Publish handles both draft-promote and revert-to-superseded; dismiss refuses on published versions.
- **Revert audit row.** Reverting to an older published version now writes a new `MetricVersion` record with `source: "revert"`, `state: "published"`, `current: true`, copying the reverted-to instruction and rubric. The older version stays untouched (still published, not current). History reads linearly: v1, v2, v3 (was current), v4 (revert to v1). Wired through web `publish_draft`, REST `POST /metric_versions/:id/publish`, and MCP `metric_versions_publish`. New "Reverted" amber chip on the metric show table.
- **API reference page** got a new Calibrations tab, expanded Runs and Metrics panels, and a Metric Versions subsection. The MCP tool count chip is wired to `CompletionKit::McpDispatcher.tool_definitions.size` so it stops drifting on every release. Authentication card carries the pagination + tag-filter conventions inline.
- **Starter metrics layout polish.** "Skip the blank page" headline (kicker on populated, h2 on empty). 4-column grid (2-col tablet, 1-col mobile). Em dashes purged from the five rubric descriptions.

### Changed

- **`Run#start!` refuses to wipe responses on running or completed runs.** Previously `start!` unconditionally called `responses.destroy_all` and reset progress. The web UI was safe (Start / Retry buttons only render for pending or failed runs), but the REST API (`POST /api/v1/runs/:id/generate`) accepted it on any status, so a scripted client could double-fire generate and lose all the succeeded rows from the first call. Now refuses unless status is `pending` or `failed`. For completed runs use `rerun`, for partial failures use `retry_failures`, for re-judging use `regrade`. Returns 422 with a message naming all three alternatives.
- **`JudgeReviewJob.perform` takes `run_id` as a third argument.** The per-run concurrency cap was previously looking the `run_id` up via `Response.find_by` on every enqueue, ~300 extra SELECTs at start time for a 100-row by 3-metric run. Callers pass `run_id` through; fallback to the old lookup preserved so jobs enqueued before the deploy still drain cleanly.
- **Internal refactor: `HasJobStatus` concern** extracted from `Response` and `Review`. Both models previously duplicated `STATUSES`, `TERMINAL_STATUSES`, `terminal?`, `succeeded?`, `error_payload`, `set_default_status`, and the status inclusion validation. Now in `CompletionKit::HasJobStatus`. The two external references (`Run#outstanding_work_zero?`, `Response#fully_reviewed?`) point at `HasJobStatus::TERMINAL_STATUSES` directly.
- **Internal refactor: Turbo broadcasts moved into model `after_save_commit` callbacks.** `Response` and `Review` now broadcast their own row updates and (on terminal status transitions) the run-level progress repaint via callbacks instead of every job manually calling `run.broadcast_response_update(response)` and `run.broadcast_progress` after each save. 8 manual broadcast call sites in `GenerateRowJob` and `JudgeReviewJob` removed.
- **`Run`'s broadcast methods are public.** They were marked private but called from jobs and controllers via `run.send(:broadcast_X, ...)`, wishful encapsulation. Now plain methods on the public surface.

### Removed

- Dead `ck_run_status_label` helper (zero production callers; `_status_header.html.erb` uses the inline `ck-status-badge` classes now). `ck_run_dot` stays; it's still used by `_row.html.erb`.
- Dead `unless defined?(...)` job-class placeholders at the top of `generate_row_job_spec.rb` and `judge_review_job_spec.rb`. They existed to survive load-order during the multi-PR rollout when those jobs didn't exist yet; both real classes have shipped long since.

## [0.6.0] - 2026-05-28

### Added

- **Cross-run comparison view** at `GET /runs/:id/compare`. Picker lists other completed runs on the same dataset + prompt; selecting one renders a side-by-side per-case table with A score / B score / signed Δ / version chip per side. Pairing is by `input_data` so a regrade against the current judge can be diffed against the original scoring. Compare button on the run-show action bar of completed runs.
- **Regrade-only flow** at `POST /runs/:id/regrade`. `Run#regrade!` clears each succeeded review's score and metric_version_id stamp, dispatches `JudgeReviewJob` for every (succeeded response, attached metric) pair, and lets the run's status state machine settle via `RunCompletionCheckJob`. The stale-versions banner on the run show page now offers Re-grade with current judge (primary, cheap) and Re-run from scratch (secondary, full regeneration) side by side.
- **Pinned cases feed `MetricVariantGenerator`'s meta-prompt.** Improve-the-metric now passes the metric's `few_shot_examples` to the model under a "Pinned cases the judge already references" section, telling the model the new rubric must remain consistent with what the operator already pins (must produce roughly the human_score, not the judge_score, on those inputs).
- **Lifetime gate on Improve the metric.** Previously the button was disabled when the current `MetricVersion` had zero disagreements, even if v_old held dozens. The gate now counts all-version disagreements; `MetricCalibrationExamples` falls back from current-version-scoped to all-version-scoped when the current pool is empty so the model still has data to work with.
- **Revert-aware flash** on the publish_draft action. When the target was already published (revert), the flash names the prior current version and acknowledges that pinned cases still flow to the judge and that calibration verdicts collected against the demoted version stay tied to it.
- **Zero-state calibration line acknowledges prior versions.** "Needs 10 verdicts on the judge's scores. (18 verdicts on prior versions, tied to that version's history.)"

### Changed

- **Cases-to-learn-from version chip** now renders whenever any row's `metric_version_id` differs from the metric's current version (was: only on lists with multiple distinct versions). Catches the case where every disagreement is on a single non-current version after a revert.

### Removed

- **Backward-compat aliases from 0.5.43 / 0.5.44 are gone.** `CompletionKit::JudgeVersion` no longer exists as an alias for `CompletionKit::MetricVersion`; `Calibration#judge_version` / `judge_version_id` aliases are gone; the `judges_compare` MCP tool no longer accepts `judge_version_a_id` / `judge_version_b_id` (use `metric_version_a_id` / `metric_version_b_id`). The 0.6.0 cut is the deadline. If you were ignoring the deprecation warnings, this is the breaking release.

## [0.5.44] - 2026-05-28

### Added

- **Reviews carry `metric_version_id`.** New `bigint` + index on `completion_kit_reviews`. `JudgeReviewJob` stamps the current `MetricVersion.id` on every new review, so each judge score now has a clean FK to the exact metric configuration that produced it (not just an `instruction` text snapshot). Migration backfills existing rows from each metric's current published version.
- **Stale-version surfacing across the run + response detail pages.** Each metric review card on the response detail page now wears a `v_n` source chip; when the review's `metric_version_id` doesn't match the metric's current published version, the chip dims to the `past` variant, the card gets a warning left-border, and a one-line note reads "Scored against a superseded version of this metric. The live judge may score this differently." On the run show page, when any review in the run is stale, a banner appears naming each metric (`Accuracy (scored by v1, v3; live is v5)`) with a primary "Re-run with current judge" button on completed runs.
- **`retry_failures` refuses on version drift.** Both the web action and `POST /api/v1/runs/:id/retry_failures` guard on `Run#stale_review_summary`. If any review in the run was scored against a superseded `MetricVersion`, retrying would mix two judge versions inside the same run — so the web action redirects with a flash alert pointing at "Re-run with current judge" and the API action returns `409 Conflict` with an error pointing at `POST /api/v1/runs/:id/rerun`. No failed responses get reset, no `GenerateRowJob`s enqueue.
- **`Review#stale_against_current_judge?`** model method and **`Run#stale_review_summary`** for consumers that want to surface their own UI on top of the staleness signal.

### Changed

- **`JudgeVersion` renamed to `MetricVersion` throughout.** The model was a snapshot of a metric's configuration (instruction + rubric_bands), not of "the judge" (which is an LLM model identifier). Renamed: table `completion_kit_judge_versions` → `completion_kit_metric_versions`, FK `Calibration#judge_version_id` → `metric_version_id`, model `CompletionKit::JudgeVersion` → `CompletionKit::MetricVersion`, service `JudgeVariantGenerator` → `MetricVariantGenerator`, helper module `JudgeCalibrationExamples` → `MetricCalibrationExamples`. Kwarg `MetricCalibrationStats.for(metric, judge_version:)` is now `metric_version:`. Backward-compat aliases left in place for one minor release: `CompletionKit::JudgeVersion` is the renamed class, `Calibration#judge_version`/`judge_version_id` still read, MCP tool `judges_compare` accepts either `metric_version_a_id` or `judge_version_a_id` (same for `b`). One migration renames table + column + four indexes.
- **Edit-form save creates a real draft instead of writing `metric.instruction` directly.** Previously the `after_update :fork_draft_judge_version` callback fired on every metric edit, which meant the live `metric.instruction` was already updated by the time the "Draft pending" UI claimed there was a pending change — the publish button was a no-op. The callback was removed; `MetricsController#update` is now explicit: meta attrs save in place, judge content (instruction + rubric_bands) creates a real `source: "edit"` draft when the metric has reviews against it, and stays in place (with the current published version synced) when it doesn't. Publishing the draft is now the actual act of pushing the change live.
- **Edit form pre-populates from the existing edit-draft** so re-edits build on the unpublished work instead of clobbering it.
- **Edit-draft and suggestion-draft banners coexist** on the edit form when both pending drafts exist. The earlier `if edit_draft && !suggestion` guard silently hid the edit-draft. Both banners now render with independent Publish / Discard / Take everything controls.
- **`JudgeReviewJob` gates `few_shot_payload` on `judge_calibration_enabled`.** Pinned cases no longer reach the judge prompt when the feature flag is off.
- **Trust panel's "Give another verdict" target excludes verdicts on the current version only.** Previously the `verdicted_ids` query crossed all versions, so after publishing a new version you wouldn't get pointed back at responses you'd already verdicted on an older judge — even though those old verdicts no longer count toward the new judge's calibration.
- **"Cases to learn from" version chip renders only when the list contains a mix of versions.** Redundant chip noise on lists where every row is on the current version is suppressed.
- **Show-page header `Review draft →` and `Review improvements →` collapsed to one `Review changes →`** with a source-aware tooltip.
- **`Improve the metric` tooltip + confirm copy stopped saying "rewrite."** The model suggests, the user accepts.

## [0.5.43] - 2026-05-25

### Added

- **Judge versioning surfaces, mirroring prompt versioning.** Each metric show page now carries a Versions table listing every `JudgeVersion` (drafts and published) with a state-aware action chip per row (Published / Publish / Make current), a Δ button per row opening a side-by-side word-diff modal of the instruction + per-band rubric_diff against the predecessor, and a Source column showing the chip-styled provenance (Original / Manual edit / AI suggestion). New `version_number` and `published_at` columns on `JudgeVersion`, plus a `publish!` model method that transactionally flips current, demotes peers, and writes the new instruction + rubric_bands back onto the Metric. The `publish_draft` controller action is now version-agnostic: it handles draft → live, suggestion → live, and revert-to-older-published in one route. The flash carries the version label ("Accuracy v3 is now the published version").
- **Calibration verdicts scope to the current judge version.** `MetricCalibrationStats.for(metric)` now defaults to the metric's current published `JudgeVersion`, so publishing a new judge via "Take everything" or "Make current" resets the trust counter to 0/10 honestly. Old verdicts stay on the version they were made against. Pass `judge_version: nil` for lifetime stats across all versions; pass an explicit version to scope to it.
- **Drafts review inline on the edit form.** Both edit-drafts and suggestion-drafts now funnel through the metric edit form. The form banner shows the relevant draft (suggestion or edit) with Discard / Take everything controls and inline word-diff panels under the instruction textarea and under each changed rubric band. The metric show page no longer carries draft panels — it shows the live state with a header button (`Review draft →` or `Review improvements →`) routing to the edit surface.
- **"What others said" disclosure on response calibration.** When verdicts from other operators exist on a row+metric, the verdict prompt surfaces a count plus a disclosure listing each prior verdict color-coded by type, with stars for the corrected score and the operator's note.
- **Forget a remembered case.** New `DELETE /metrics/:id/remove_few_shot` route. Pinned disagreements in "Cases to learn from" now render a `FORGET` button next to the `REMEMBERED` chip. `JudgeReviewJob` finally passes `metric.few_shot_examples` to `JudgeService` as `human_examples`, so pinned cases actually reach the judge prompt at grading time (a long-standing latent bug).
- **Per-case version chip** in "Cases to learn from". Each disagreement row wears a small `v2`-style chip indicating which judge version produced the score being verdicted, with `--past` dimming for verdicts on superseded versions. The display query is unscoped to show full history; the Improve-the-metric gate stays scoped to current-version disagreements via a separate count.

### Changed

- **"Trust level" → "Calibration"** across user-facing copy. Score is the per-row 1–5, verdict is the act, calibration is the aggregate signal. Shield-check icon swapped for `adjustments-horizontal` because calibration is tuning, not trust.
- **No more "row" in user-facing copy.** `View row N` → `View case N`, `Rows where...` → `Cases where...`, pin/forget tooltips reference `this case`, retry-failed button reads "Retry N failed cases", API reference dataset summary reads "N entries".
- **Mutually exclusive improvement buttons** on metric show. `Improve the metric` and `Review improvements →` never appear together; the second replaces the first when a suggestion draft exists. Regenerate moved into the edit-form suggestion banner with turbo-confirm.
- **Seed data rebuilt for signal.** Single configured operator. Per-metric disagreement notes mapped to actual seeded tickets. Per-note corrected_score offsets (sometimes off by 1, sometimes by 2, sometimes judge undersold). Multiple metrics carry version history, pinned few-shot cases, pending drafts, and varied borderline rates so the metrics index demonstrates the full range of trust states.

### Fixed

- **`row_index` populated on seeded responses** so the `View case N in <run>` link doesn't fall back to `(nil || 0) + 1 = 1` for every response, falsely collapsing different cases to "row 1".
- **Trash button height in form action bars** matches the CANCEL/SAVE row instead of being half the height with a 1-pixel icon inside.

## [0.5.42] - 2026-05-24

### Added

- **Starter metrics**. (#56) Five preconfigured rubrics — Correctness, Instruction following, Format compliance, Tone, Conciseness — surfaced as cards on the metrics index. Empty-state `/metrics` leads with the starter grid; populated `/metrics` gets an "Add a starter metric" row at the bottom showing whichever starters aren't already adopted or dismissed. Click a card to land on a preview page (name, what-this-catches, judge instruction, full 1–5 rubric); one click adopts it and redirects to the new metric's show page. Per-deployment dismissals via a new `completion_kit_starter_metric_dismissals` table (unique on `starter_key`, tenant-scoped automatically).

## [0.5.41] - 2026-05-24

### Changed

- **Disagreements list, not a table.** The "Where the judge got it wrong" table was overflowing across columns at common viewport widths (run name pushing into the judge score, arrow column crashing into group pills on the metric index). Replaced with a list of cards: one card per disagreement, `Judge [N] → Human [N]` row, note paragraph, small "run · row #N" link footer. No more column squeeze.
- **Softer copy across the calibration surfaces.** Section renamed to **Cases to learn from**. "Teach the judge" button → **Remember this**. Pinned-state chip → **Remembered**. "Teaching examples" section → **What the judge remembers**. Save-flash → "Got it. The judge will remember this next time it grades."
- **Empty disagreements section disappears.** No more "nothing here yet" card; the whole section is hidden until there's at least one disagreement to look at.
- **Metric index folds Trust level into the Name column.** Was a 5th column that broke the table at common widths (In Groups header wrapping, row arrow overlapping group pills). Trust line now reads as a small dim mono line under the metric name. Table is back to Name / Instruction / In groups / arrow.

## [0.5.40] - 2026-05-24

### Changed

- **"Improve the metric" is now one inline suggestion, not a queue.** The dedicated `/improvements` page is gone; the alternatives-waiting banner is gone; the multi-option list is gone. Clicking Improve generates a single rewrite (max 3 via MCP), wipes any prior suggestion draft, and renders one card on the metric page with the current-vs-proposed diff plus Use / Discard. The model may also rewrite the rubric bands when the disagreement signal points at rubric ambiguity. (#55)
- **Improve button is gated on signal.** Disabled until at least one row has a Disagree verdict; tooltip explains why. Stops the model from confidently producing reworded noise against zero calibration data.
- **Calibration save feedback is the button itself.** The separate "Saved ✓" badge is gone; the Save button briefly flashes green (background animates from `--ck-success` to default cyan over 1.4s) on success. No layout shift, no mobile wrap.
- **Response detail review card is flatter.** One bordered card per metric. The note-box around feedback and the bordered well around the calibration form are gone — the inputs themselves carry the structure. (#calibration UI)
- **Response JSON output gets a light syntax highlight and no longer wraps.** `ck_format_maybe_json` now tokenises the pretty-printed string and wraps keys (lavender), strings (sky blue), numbers (amber), and `true` / `false` / `null` (pink) in spans. The scroll-wrapper switched from `pre-wrap` to `pre` so long lines scroll horizontally instead of bricking the page. `\`\`\`json` fenced model responses are now unwrapped before highlighting.
- **Seed data no longer reads like an LLM wrote it.** Stripped 34 em-dashes and 2 en-dashes from `standalone/db/seeds.rb` and `app/services/completion_kit/onboarding/sample_data.rb`; paired em-dash asides became parens, single em-dashes became `. Capitalised next` sentence breaks, run-name em-dashes were dropped.

### Fixed

- **Propshaft hosts can load the engine stylesheet.** `application.css.erb` is now a plain `application.css` with three explicit `@font-face` rules pointing at the woff2 assets. Propshaft's CssAssetUrls rewrites the digests automatically. (#53)
- **Onboarding progress bar no longer carries a redundant hairline under it.** (#54)
- **Disagree click without a score no longer hits a top-page flash.** The score form is revealed inline; real validation failures render inline in the calibration block. (#55 follow-up)
- **Mobile**: 5-star review row no longer wraps; action-bar `button_to` forms go block on mobile so they line up with link buttons; verdict prompt stacks vertically; the Saved feedback no longer wraps "✓" onto its own line.

## [0.5.39] - 2026-05-23

### Fixed

- **Propshaft hosts can now load `application.css`.** (#53) `app/assets/stylesheets/completion_kit/application.css.erb` is now a plain `.css` file with three explicit `@font-face` blocks pointing at `completion_kit/jetbrains-mono-{400,500,700}.woff2`. Propshaft's `CssAssetUrls` compiler rewrites those `url()` refs to digested paths at build time; Sprockets resolves them at request time too. No more ERB requirement on the host. Hosts running a Propshaft-compat workaround (pre-rendering the ERB file to `tmp/` on boot) can remove it.
- **Disagree click no longer fires a validation error from across the page.** Clicking the disagree pill without a score doesn't try to save anymore — it reveals the score slider + note form inline so the user supplies the data before submitting. Real validation failures (e.g., a score outside 1–5) render inside the calibration block via Turbo Stream, not in the page-level flash. Slider input gets `required` so the browser blocks the bad case too.
- **Publishing a judge draft actually swaps the live judge text.** Was previously flipping only the `state` flag; now the publish transaction copies the draft's instruction and rubric onto the metric.
- **Per-variant Publish buttons publish the variant they sit next to.** The action now takes `draft_id`; was always grabbing the newest draft.
- **Review stars no longer wrap on mobile.** The 5-star row inside the review-card header is `flex-wrap: nowrap`; the header itself stacks vertically below 640px.

### Changed

- **Calibration copy de-jargoned for non-experts.** "Judge trust" → "Trust score" everywhere. "Few-shot" → "teaching example". "Suggest rewrites" → "Improve the metric". "Suggested rewrites" → "Suggested improvements". Per-verdict tooltips spell out what agree / disagree / borderline mean. The verdict counter on the response page links to the metric's trust score. The "Improve the metric" generator now feeds both disagreements *and* rubric-ambiguous (borderline) cases into the meta-prompt, with the latter clearly labeled — borderlines are a directly actionable signal about rubric ambiguity. `MAE` and `κ` no longer appear in the visible trust panel; they're still in the MCP / API payload.
- **Metric index gains a Trust score column.** At-a-glance state per metric (`No verdicts yet`, `N / 10 verdicts`, or `~82% ±12 pt · early / settled`) so users can scan which metrics need attention without clicking in.
- **Instruction box on the metric show page is no longer nested.** Was a `.ck-card` wrapping a `.ck-note-box` (box-in-a-box). Now one container, simple-format content directly inside.

## [0.5.38] - 2026-05-23

### Fixed

- **Publishing a judge draft now actually swaps the live judge text.** The publish action used to flip the version's `state` column but never copy the draft's instruction/rubric back to the metric, so publishing a suggested rewrite changed nothing the judge actually saw. Now the publish transaction copies the draft's text onto the metric.
- **Per-variant Publish buttons now publish the variant they sit next to.** They were all hitting the same endpoint, which always grabbed the newest draft. The action now takes a `draft_id` and each button passes its own.

### Changed

- **Non-expert copy across the calibration UI.** "few-shot" reads as "teaching example" everywhere it was user-facing. "variants" became "alternatives" / "rewrites". "provisional" became "early read". The borderline statistic now reads `X% said "unclear"` with a tooltip explaining what to do about it. Each verdict pill gained a per-button tooltip describing what it means. `MAE` and `κ` were removed from the visible trust panel; they're still computed and available via MCP / API.
- **Judge trust column on the metric index.** At-a-glance state per metric — "No verdicts yet", "N / 10 verdicts", or "~82% ±12 pt · early / settled" — so a user can scan which judges need attention without clicking in.
- **Verdict count links to the metric's trust panel.** On the response detail page, the "N verdicts on this score" line now links to the metric show page, so users know where their input rolls up.

## [0.5.37] - 2026-05-23

### Added

- **Judge calibration · Phase 2 — Trust score.** Trust panel on the metric show page. Under 10 verdicts it's a counter (`7 / 10 verdicts · 3 more to score`); from 10 verdicts on it's a provisional rate with the Wilson 95% interval (`~80% ±18 pt · provisional`), flipping to `settled` at 30+. Pure-Ruby `CalibrationMath` module (Wilson, MAE, Pearson, quadratic weighted Cohen's kappa) backed by a `MetricCalibrationStats` service — no new gem dependency. (#33)
- **Judge calibration · Phase 3 — Disagreements & few-shots.** "Disagreements" section on the metric show page lists every disagree verdict with judge vs. human scores and notes; one-click "Add as judge few-shot" promotes a row to the metric's `few_shot_examples` jsonb-style column. Borderline-rate badge on the trust panel now picks its color band (`ok` ≤15%, `warning` >15%, `danger` >30%) with the "Rubric ambiguous" tooltip. (#34)
- **Judge calibration · Phase 4 — Version state + compare.** `JudgeVersion` gained `state` (draft/published) and `source` columns. Editing a metric's instruction or rubric forks a non-current `draft` snapshot via an `after_update` callback; the show page renders a "Draft pending" banner with a Publish button that flips the latest draft to current+published in a transaction. New MCP tools `judges_replay` (thin wrapper that creates a judge-only run with the supplied metric / dataset / judge_model) and `judges_compare` (side-by-side stats, delta, and a recommendation: `need_more_data` / `recommend` / `hold` / `no_change`). (#35)
- **Judge calibration · Phase 5 — Auto-suggest rubrics.** `JudgeVariantGenerator` builds a meta-prompt from the metric's instruction, rubric, and recent disagreements, asks the configured judge model for 1–5 rewritten instructions, and persists each as a draft `JudgeVersion` with `source: "suggestion"`. New MCP tool `judges_suggest`, a "Suggest improvements" button on the metric show page, and an `ActiveSupport::Notifications` event `completion_kit.judge_suggestion.generated` so Stripe metering can pick it up downstream. (#36)

## [0.5.36] - 2026-05-23

### Fixed

- **Ollama model discovery 404.** `ModelDiscoveryService` was sending GET requests with leading-slash paths (`/models`, `/chat/completions`), which Faraday treats as absolute paths from the host root. With an endpoint configured as `http://localhost:11434/v1`, that lopped off the `/v1` and hit `http://localhost:11434/models`, which Ollama doesn't expose — discovery failed with `404 page not found`. Now the service strips a trailing `/v1` from the configured endpoint and requests `/v1/models` and `/v1/chat/completions` explicitly, so it works whether you configure the endpoint with or without the `/v1` suffix.

## [0.5.35] - 2026-05-22

### Added

- **Judge calibration · Phase 1.** Three pill buttons (agree / disagree / borderline) on every scored row in the per-row review. Choosing "Disagree" surfaces a slider preset to the judge's score plus a note field; "Borderline" surfaces a note-only form. A small "X verdicts collected" counter renders next to the metric once at least one verdict lands. New tables `completion_kit_judge_versions` and `completion_kit_calibrations`, REST endpoints under `/api/v1/runs/:run_id/responses/:response_id/metrics/:metric_id/calibrations`, MCP tools `calibrations_create` and `calibrations_list`, and the `CompletionKit.config.judge_calibration_enabled` feature flag (default on). (#32)

## [0.5.34] - 2026-05-22

### Security

- **Provider endpoint hardening.** Stored endpoints are re-validated against the SSRF ruleset every request, not only at write time, so a host that flips `allow_loopback_endpoints` to false later cannot still reach a previously-saved `127.0.0.1` endpoint. The Ollama default localhost fallback is gated on that same flag, and `for_provider` no longer leaks deployment-level ENV defaults to tenants when `tenant_scope` is set. (#52)

### Accessibility

- **Index-table rows are keyboard-accessible.** The primary record name in every index table (prompts, runs, datasets, metrics, metric groups, tags) is now a real `<a>` link, so tab + Enter activates the row. Header cells gained `scope="col"`. (#49)
- **Form errors announce.** Every form's error-summary div now carries `role="alert"`, and text inputs gain `aria-invalid` plus `aria-describedby` pointing at a sibling error paragraph when the field has errors. Helpers `ck_field_aria` and `ck_field_error` keep it terse at the call site. (#50)
- **Live regions on async surfaces.** `#run_status_panel` and `#run_status_header` are `aria-live="polite"` so Turbo Stream updates get announced; the failed-run flash gets `role="alert"`. The response row first cell wraps in a focusable link, breadcrumbs carry `aria-label="Breadcrumb"`, and the tag picker checkbox is keyboard-focusable with a CSS visually-hidden class instead of the `hidden` attribute (which removed it from the a11y tree). (#51)

## [0.5.33] - 2026-05-22

### Added

- **Self-hosted JetBrains Mono.** The engine bundles the JetBrains Mono webfont (regular, medium, bold) as engine assets and loads it through a local `@font-face`. The previous remote `@import` from Google Fonts is gone, so visitors' IPs no longer reach Google before any consent. (#43)
- **Skip-to-content link and primary-nav landmark** in the engine layout, so keyboard and screen-reader users can bypass the topbar (WCAG 2.4.1). (#48)
- **Live region for the provider-models refresh status** so screen readers announce progress and completion. (#48)
- **Privacy docs.** `docs/privacy/pii-inventory.md` and `docs/privacy/data-flow.md`: a host-actionable inventory of personal data in engine tables and what the engine sends to and persists from model providers. (#45, #46)
- **Accessibility audit doc.** `docs/accessibility/audit-2026-05-22.md`: a pattern-level audit of the authenticated engine pages. (#48)

### Changed

- **`--ck-dim` raised to `#7a8aa3`** (about 5.4:1 on `#080b14`), so the dim text token clears WCAG AA contrast. (#47)
- **Onboarding-dismiss cookie** is now written with explicit `secure: Rails.env.production?, same_site: :lax`, so the flags do not depend on host middleware. (#44)
- **Settings dropdown panel** no longer carries `role="menu"`. The panel is a list of links, not an ARIA menu widget, so the role mismatch is gone. (#48)

## [0.5.32] - 2026-05-21

### Fixed

- **Topbar nav offset.** 0.5.31 shifted the topbar navigation with a `position` offset that applied at every viewport width, including the mobile hamburger menu. The nav is now a plain flex item with a small top padding, so it stays correctly placed and fully responsive.

## [0.5.31] - 2026-05-21

### Added

- **The dashboard is a first-class engine page.** `CompletionKit::DashboardController#show` (route: `dashboard`) renders the assembled dashboard — workspace totals, run activity, the worst-metric and failures cards, version-over-version prompt changes, and recent runs. Any host that mounts the engine gets it; the page previously existed only in the bundled standalone app.
- **Concept tips on the onboarding checklist.** Each setup step shows an info popover defining its concept (provider credential, dataset, prompt, run).

### Changed

- **A configured workspace lands on the dashboard.** The engine onboarding page redirects a set-up or onboarding-dismissed workspace to the dashboard instead of the flat prompts list.

## [0.5.30] - 2026-05-20

### Added

- **Onboarding concept tips.** The setup checklist's step cards now carry inline info popovers explaining the core concepts as they are mentioned (provider credential, prompt, dataset, run, response, metric). Click the icon next to a term for a short definition.
- **Dockerfile for the standalone app.** The bundled standalone app ships a `Dockerfile`, so it can be self-hosted with no Ruby toolchain on the host. The README's Docker section covers building, the required environment variables, and generating the encryption keys with `openssl`.

### Changed

- **Settings is a cog-icon menu.** The topbar Settings control is now a cog icon that opens a dropdown holding Getting started, API, Providers, Tags, and Sign out. API and Sign out moved off the top-level nav into this menu, which closes when you click outside it. "Log out" is now "Sign out", to match the "Sign in" wording on the login screen.

## [0.5.29] - 2026-05-18

### Security

- **Rate limiting across every request surface.** The REST API and the MCP endpoint (120 requests per minute per IP) and the web UI (300 per minute per IP) are now rate limited, closing the brute-force and abuse gap left after the login limit. The caps are tunable with `config.api_rate_limit` and `config.web_rate_limit`, and documented in the README and the generated initializer.

## [0.5.28] - 2026-05-18

### Security

- **MCP errors no longer leak internals.** An unexpected exception in the MCP endpoint returned its raw message to the client. The catch-all now returns a generic "Internal error" and reports the real exception server-side.
- **Open access blocked in every deployed environment.** When no authentication is configured, the engine previously left routes open in any environment other than production. It now blocks every non-local environment; development and test stay open for convenience.

## [0.5.27] - 2026-05-18

### Security

- **SSRF guard on provider endpoints.** A `ProviderCredential`'s `api_endpoint` is now validated to resolve to a public or loopback address. Private ranges (10/8, 172.16/12, 192.168/16) and the link-local range (169.254/16, which covers cloud metadata) are rejected, as are non-http(s) URLs. Loopback stays allowed so Ollama on localhost keeps working.
- **Login rate limiting.** The standalone app's sign-in action now allows 10 attempts per 3 minutes per IP, blunting password brute-force.

## [0.5.26] - 2026-05-18

### Fixed

- **Mobile list tables.** Every list table (metrics, metric groups, datasets, tags, run responses) scrolled horizontally on a phone and clipped content off the right edge. On mobile each row now becomes a stacked block with a small column label above each value, so a bare cell still reads clearly. Run tables keep their tailored mobile layout.
- **Mobile ignored-items popover.** Anchored to a small mid-footer toggle, the popover spilled off the left edge and clipped the metric names. On mobile it is now a bottom sheet pinned to the viewport, where nothing can clip.

## [0.5.25] - 2026-05-18

### Fixed

- **Mobile layout, page-by-page audit at true phone width (390px).** Fixes for issues that overflowed the viewport or clipped text on a phone: the dashboard prompt-changes row stacks instead of truncating the prompt name to a couple of characters; the runs table becomes a stacked block layout (name + sub-line, then score / timestamp / arrow) instead of a six-column horizontal scroll; long API endpoint URLs and the API-reference auth-token chip wrap instead of forcing page overflow; the onboarding page's decorative field is clipped; and the API-reference tabs nav fits its column instead of being cut off.

## [0.5.24] - 2026-05-16

### Changed

- The dashboard's ignored-metrics flyout is now sorted by baseline score, highest first (metrics with no baseline last).
- The ignored-items popover has a styled scrollbar — thin, rounded, on-brand — instead of the raw browser default.

## [0.5.23] - 2026-05-16

### Fixed

- **Thread race in Turbo-broadcast renders from background jobs.** Worker threads rendering engine partials for Turbo broadcasts raced the engine's lazy route set during its first materialization and raised `undefined method 'run_response_path'` — failing judge reviews and prompt-run rows under a multi-threaded worker. `CompletionKit::Engine.warm_routes!` now materializes the route set once, single-threaded, before the concurrent renders. Production was unaffected (`eager_load` finalizes routes at boot); the bug surfaced on any worker running with lazy route loading.

## [0.5.22] - 2026-05-16

### Changed

- **Responsive mobile layout.** Below 640px the topbar nav collapses to a hamburger menu (a no-JS `<details>` disclosure); result tables scroll horizontally within their card instead of forcing the whole page wider; and page headers stack the title, intro text, and action button instead of squeezing the intro into a sliver.

## [0.5.21] - 2026-05-16

### Changed

- The dashboard's ignored-items popover is larger and more spread out — each row stacks the metric name above its baseline score with more breathing room.

## [0.5.20] - 2026-05-16

### Added

- **Dismissible dashboard alerts.** The worst-metric and failures cards can now be triaged:
  - **Ignore a worst metric** once you've acted on it. The card surfaces the next-worst metric instead. The metric's window average is snapshotted at ignore time — it stays hidden while it holds at or above that baseline, and **resurfaces automatically if it regresses below it** (the stale dismissal is cleared so re-ignoring re-snapshots). A genuinely-worse other metric still appears on its own.
  - **Ignore a failure.** Failures are finished events, so a failure dismissal is permanent until un-ignored.
  - Each card has an **"N ignored" flyout** listing what's been dismissed, each with an un-ignore button. Ignore and un-ignore update the dashboard in place via Turbo Streams — no reload.
- New polymorphic `CompletionKit::DashboardDismissal` model and `CompletionKit::DashboardDismissalsController`.

### Changed

- **The narrow "Failed reviews" card is now a unified "Failures" card.** It previously counted only failed judge reviews; it now covers all three failure surfaces over the 7-day window — failed runs, failed generations, and failed judge reviews — each with its cause and a deep link. `DashboardStats.failed_review_count` is replaced by `DashboardStats.failures`.
- `DashboardStats.worst_metric` now groups by metric id (was metric name) so dismissals can be matched, and skips dismissed metrics.
- The standalone dashboard layout now loads Turbo, so dashboard actions update in place.

## [0.5.19] - 2026-05-15

### Added

- **Dashboard analytics** (issue #29). The standalone dashboard now surfaces what's actually happening in the workspace via a new `CompletionKit::DashboardStats` service:
  - **Activity** — a 14-day runs-per-day sparkline; the busiest day(s) get the bright accent.
  - **Worst metric** — the lowest-average judge metric over the last 7 days, with a deep link to its worst-scoring response. The "what should I work on?" answer.
  - **Failed reviews** — a 7-day count of terminally-failed reviews (parse failures, truncations, provider errors). Green when clean, red when not.
  - **Prompt changes** — per prompt family, the most recent measurable version-over-version score change, gains *and* regressions. Compares the latest draft against the published version when a draft sits ahead, or the published version against its predecessor when the latest is published. `▲`/`▼` with green/red deltas. Has an instructive empty state so a fresh workspace never shows a blank panel.
  - Analytics are gated behind `> 5` runs so brand-new workspaces just see the stat ribbon and recent runs.

### Changed

- **Dashboard redesign.** The two oversized prompt/run count cards are replaced by a slim four-segment stat ribbon (Prompts · Metrics · Datasets · Runs — matching the nav order), and the analytics cards become the visual hero with a consistent footer-pinned layout and a subtle staggered page-load reveal (`prefers-reduced-motion` respected).
- **Standalone layouts now use the engine's standard brand.** The dashboard, login, and topbar were still rendering an old `logo-device.svg` / `logo.svg` and a plain wordmark. They now use the engine's puzzle-piece `logo.png` + two-tone "Completion**Kit**" wordmark and `favicon.ico`, consistent with every engine page. The two dead logo assets were removed.

## [0.5.18] - 2026-05-15

### Fixed

- **Engine path helpers still raised `UrlGenerationError` under a dynamic mount scope** (issue #30, reopened). 0.5.17 passed `**url_options` whole, but `url_options` carries the host's dynamic segments nested inside `_recall` (`{controller:, action:, org_slug: "acme"}`). The engine's url_helpers won't pull a required segment out of the nested recall hash — it has to arrive as a direct kwarg. `ck_run_path` / `ck_prompt_path` / `ck_dataset_path` now go through `ck_engine_path_options`, which lifts `url_options[:_recall]` minus `:controller`/`:action` into explicit kwargs. A host mounting the engine under `scope "/orgs/:org_slug"` now resolves `org_slug` automatically; standalone (no recall segments) is unaffected.

## [0.5.17] - 2026-05-15

### Fixed

- **`ck_run_path` / `ck_prompt_path` / `ck_dataset_path` ignored the host's `default_url_options`** (issue #30). When a host app mounts the engine under a dynamic scope (e.g. `scope "/orgs/:org_slug"`), the engine path needs `:org_slug` filled in, but the proxy call had no access to the controller's `default_url_options` and raised `ActionController::UrlGenerationError: missing required keys: [:org_slug]`. All three helpers now thread `url_options.except(:host, :protocol, :script_name)` through to the engine route helper, so any dynamic segment the host injects via `default_url_options` resolves automatically. Standalone keeps working unchanged.
- **Run detail page row count** showed the literal line count of the CSV instead of the actual row count, which exploded to "213 rows" on a 10-row dataset whose `actual_output` column contains multi-line JSON. Now uses `Dataset#row_count` (which CSV-parses properly).

### Changed

- **Metrics index name column** drops `white-space: nowrap` so long names like "Vehicle Comparable Sales Relevance" wrap inside the 18rem column instead of bleeding into the instruction column.

## [0.5.16] - 2026-05-14

### Changed

- **Tables no longer overhang their containers.** Every `.ck-results-table` now uses `table-layout: fixed; width: 100%` with explicit per-table column widths so the table can never spread beyond its parent. Previously `table-layout: auto` would distribute slack based on content width, which let long run names or long descriptions push the table 30–50px past the page section's right edge. Covers `ck-runs-table` (runs index, dataset show, prompt show, dashboard recent runs), `ck-prompts-table`, `ck-metrics-table`, `ck-tags-table`, `ck-responses-table`, the previously-unclassed datasets-index, metric-groups-index, and prompt-versions/suggestions tables (now `ck-datasets-table`, `ck-metric-groups-table`, `ck-prompt-versions-table`, `ck-suggestions-table`), plus `ck-model-table` on the provider credentials page.
- **Tag pill brightness**: `.tag-mark` background mix bumped from `color-mix(... 24%, transparent)` to `38%`. Bright-source colors (electric-cyan, mint, burnt-orange) and darker-source colors (deep-emerald, deep-indigo) now sit closer in visual weight so a row of multi-colored tags doesn't read as "some are washed out."
- **Standalone home page Recent-runs section** is back to a plain section without an outer `.ck-card` wrap. The previous nested-card layout produced two competing rounded borders; the table's own border is now the only frame, matching how runs/index renders.

## [0.5.15] - 2026-05-14

### Fixed

- **Judge parse failures no longer silently become 1-star reviews** (issue #27). `JudgeService#parse_judge_response` now raises `CompletionKit::JudgeParseError` when the judge response can't be parsed instead of returning `{ score: 1, feedback: "Could not parse..." }`. `JudgeService#evaluate` likewise propagates LLM-client errors (`"Error:"`-prefixed responses) and configuration errors instead of swallowing them as score 1. `JudgeReviewJob`'s `rescue_from(StandardError)` already records terminal failures with `status: "failed"`, `ai_score: nil`, and `error_class`/`error_message` populated, so parse failures now show up as distinct failed reviews in the UI and are naturally excluded from averages. Combined with 0.5.14, the empty-content case (most volume) and the malformed-non-empty case (edge case) both surface as real failures instead of silent floors at 1.0.
- **Standalone host app's home page** crashed on judge-only runs because `run.prompt.name` was unguarded. Now shows "Judge-only" inline.

### Changed

- **Standalone home page recent-runs table** now renders via the engine's shared `completion_kit/runs/table` partial — same look, pips, truncation, judge-only handling, and metadata layout as runs/index, dataset/show, and prompt/show.
- **Engine shared partials** now reference engine routes through new `ck_run_path` / `ck_prompt_path` / `ck_dataset_path` helpers (resolved via `CompletionKit::Engine.routes.url_helpers`) so they render correctly from host-app view contexts, not just from inside the engine.
- **Favicon**: added a `#64748b` grey halo around the tilted puzzle piece so it reads at small sizes against pale browser chrome.

## [0.5.14] - 2026-05-14

### Fixed

- **Judge calls on reasoning models silently returning 1-star** (issue #28). Reasoning models (GPT-5 Pro family, o-series, etc.) charge reasoning tokens against `max_tokens` in chat-completions. With our previous default of 1000, ~40% of BB-sized judge prompts hit `finish_reason: "length"` and a non-trivial share returned empty visible content, which the parser then coerced to score 1.0. Two changes:
  - `OpenRouterClient` and `OpenAiClient` default `max_tokens` bumped from 1000 to 8192. Pay-as-you-use providers only bill actual completion tokens; the higher cap only matters when the model needs the headroom.
  - Both clients now treat truncation and empty content as errors instead of returning a blank string. OpenRouter: `finish_reason: "length"` → error. OpenAI Responses API: `status: "incomplete"` (with reason from `incomplete_details`) → error. Empty content after `.strip` → error. `JudgeService` already raises on `"Error:"`-prefixed responses, so these surface as real review failures rather than silent 1-stars.

## [0.5.13] - 2026-05-14

### Changed

- **Response detail page**: Input / Response / Expected blocks now cap at 28rem and scroll inside a wrapper `<div>` instead of overflowing the page. Inline JSON is pretty-printed automatically when the payload starts with `{` or `[`. Big BB-style judge inputs are readable without dwarfing the rest of the page.
- **Runs table**: long run names truncate with ellipsis at 27rem so the metadata columns (responses, metrics, avg score, when) stay clustered next to the name instead of being pushed to the page edge. Same partial across runs/index, dataset/show, and prompt/show.
- **Dark color-scheme**: `:root` declares `color-scheme: dark` so native scrollbars on inner scroll regions (dataset CSV preview, response code blocks) match the browser's main scrollbar instead of falling back to light-mode overlay scrollbars on Safari.

## [0.5.12] - 2026-05-14

### Fixed

- **MCP "Session not initialized" on multi-tenant hosts and after activity gaps**, even though 0.5.10 moved sessions to the database. Two causes, both fixed:
  - `CompletionKit::ApplicationRecord` applies the host app's `tenant_scope` as a default_scope to every engine model — including `McpSession`, whose table has no `organization_id` column. Every session lookup was either erroring (no such column) or short-circuiting to `WHERE 1=0`, returning the live session as "not found". `McpSession` now goes through `.unscoped` on every query so the per-tenant default_scope can't touch it. Sessions are per-CONNECTION, not per-tenant.
  - The 1-hour TTL was a hard wall: a session that initialized at T+0 died at T+1h regardless of activity. `McpSession.active?` now slides `expires_at` forward on each call (only after the halfway mark, to avoid writing the row on every tool call). Idle for > TTL still expires; active conversations don't.

## [0.5.11] - 2026-05-14

### Added

- **Judge-only runs** (issue #26): grade a pre-existing dataset column instead of generating new outputs. `prompt_id` is now optional on a Run; when omitted, each Response's text is read from `row[output_column]` (default `actual_output`, overridable) and the judge runs as normal. Drives the "I already have 1,000 production outputs I want to score" workflow — no need to regenerate the artifact you're trying to grade. Available via REST (`POST /api/v1/runs` with `output_column`, no `prompt_id`), MCP (`runs_create`), and a new "Judge-only run" checkbox on the create-run form that swaps the Prompt field for an Output-column input. **Host apps need `bin/rails completion_kit:install:migrations && db:migrate` to pick up the new column.**

### Changed

- **README — "Three ways to run it"** framing. The Quick Start now leads with hosted ([completionkit.com](https://completionkit.com), recommended), then self-hosted standalone, then Rails engine — same engine across all three. Lead callout pushes Cloud directly.

## [0.5.10] - 2026-05-14

### Added

- **API reference: "Your <X>" cards in every section.** The Prompts panel's per-prompt cards are now mirrored in **Runs** (last 10, with status), **Responses**, **Datasets** (with row count), **Metrics** (with truncated instruction), **Metric Groups** (with metric count), **Tags** (with color), and **Providers** (with model count) — each card shows the resource name, a meta chip, and the real `GET /api/v1/X/:id` URL with a copy button. New optional collection locals on `_body.html.erb` so a host can still render the generic public docs with just `base_url:`.
- **Download CSV button on the dataset show page.** Slugified filename from the dataset's name (`"Customer Tickets — sample"` → `customer-tickets-sample.csv`), falling back to `dataset-<id>.csv` when the name slugifies to blank.
- **New brand mark** — trimmed puzzle-piece symbol replaces the old `logo.svg`; "Completion" in `#3AD0E6` and "Kit" in `#AFEDF7` (the symbol's palette); favicon is a clean single tilted piece, sized as a multi-res `.ico`.

### Fixed

- **MCP sessions survive Puma restarts and deploys.** Sessions were stored in `Rails.cache`; with the default in-process `:memory_store`, every restart silently wiped every active MCP session and long-lived clients hit "Session not initialized" until they re-init'd. They're now in a `completion_kit_mcp_sessions` table — durable, cross-process, no new dependency. Expired rows are opportunistically pruned on every new initialize. **Host apps need to run `bin/rails completion_kit:install:migrations` and `db:migrate` to pick up the table.**
- **Compact metrics field when there are no metrics yet.** The empty `<p id="metrics-hint">` placeholder used to add a ~50px ghost gap between the Metrics label and the "No metrics yet" warning; it only renders when there *are* metrics for the JS to talk about now, and the field's wider gap + bottom margin only apply via `:has(.ck-metric-checkboxes)`.

### Changed

- **One prose font size across the app.** `.ck-copy / .ck-meta-copy / .ck-note / .ck-hint` were `0.95rem`, `.ck-mcp-tool__desc` `0.8rem`, `.ck-mcp-install-card__header` and `.ck-api-prompt-card__desc` `0.78rem` — all now `0.9rem`. Headings, kickers, mono identifiers, code blocks, and field hints (their own smaller tier) untouched.
- **Prompts show page: vertical rhythm + grouped metadata.** Tags moved up into the page header alongside name / version / model / description / endpoint; the prompt template `<pre>` gets a `.ck-code--prompt` modifier (1.5rem padding, 1.75 line-height); the Prompt section now takes `ck-card--spaced` for a consistent rhythm above. Identity → template → versions → runs each read as distinct regions.
- **On-theme scrollbars on the dataset CSV preview** (webkit + Firefox/Safari 17+) so the preview wrap stops being a bright UA strip in the middle of the dark UI.
- **Single shared partial for the runs table.** `runs/index`, `datasets/show`, and `prompts/show` were hand-copying the same `<table class="ck-results-table ck-runs-table">` markup; they all render `completion_kit/runs/_table.html.erb` now.

## [0.5.9] - 2026-05-12

### Fixed

- **Consistent code-example font size on the API reference page.** The `curl` examples and the MCP install snippets are rendered by the same partial but displayed at different sizes (0.9rem vs 0.72rem); they're both 0.78rem now.

## [0.5.8] - 2026-05-12

### Fixed

- **API reference tabs rendered blank.** The Metric Groups, Tags, and Providers tabs showed an empty panel — the tab stylesheet still mapped an old 8-tab layout (with a renamed `criteria` id) while the page now has 9 tabs. The `:checked → panel` rules cover all nine again, and a spec keeps the radios, panels, and CSS in sync from here on.
- **Relative timestamps no longer read "now ago".** Labels like the runs list "When" column render a complete phrase — "just now" under a minute, "3m ago" / "3d ago" otherwise — instead of appending a stray " ago" to "now".

### Changed

- **Editing only a run's name or tags no longer forks a new run.** A run that already has results forks a fresh copy only when something affecting generation or judging changed (prompt, dataset, judge model, temperature, metrics); renaming or retagging updates the run in place.
- **API reference: "Your published prompts" moved into the Prompts section.** The per-prompt URL cards used to lead the page; they're now a subsection inside the Prompts tab, after the `GET /api/v1/prompts/:id` docs — so a host rendering the docs body standalone doesn't open with a pile of prompt cards.
- **More breathing room between the run form's Metrics section and the Run tags field.**

## [0.5.7] - 2026-05-12

### Added

- **API reference page is reusable by a host app.** The docs body — prompt cards, endpoint tabs, MCP tools list, copy-paste examples — is now a standalone partial (`completion_kit/api_reference/_body`) taking `base_url:` / `token:` (default `YOUR_TOKEN`) / `real_token:` / `published_prompts:` locals, so a host can render it from its own controller: a public, crawlable docs page with placeholders, or an in-app page with the workspace's real token. The Authentication card is its own partial too, swappable via `CompletionKit.config.api_reference_authentication_partial` for hosts (e.g. multi-tenant ones) that manage their own bearer tokens. The engine's own `/api_reference` page renders identically.
- **New runs inherit the previous run's tags.** Opening the new-run form pre-selects the tags of the most recent run in that prompt's family; "Re-run" carries the source run's tags over too.

### Fixed

- **False "no worker is processing jobs" banner.** SolidQueue workers heartbeat every 60s by default, but the health check only looked back 30s — so a healthy worker was flagged as down between beats while jobs were visibly being processed. The window is now 2 minutes.

### Changed

- **More vertical breathing room in the run form's Metrics section** — the label, the hint, the "Groups" sub-header, and the group pills were bunched too tightly together.

## [0.5.6] - 2026-05-12

### Added

- **Navigable prompt version history.** The Versions table on a prompt page now lists every version with a best-score column, links each row to that version's page, badges the current one **Published** (and gives the others an inline **Publish** button), and outlines the version you're viewing. A `Δ` link opens an on-demand modal showing what changed from the previous version — the model swap as before→after chips and a word-level template diff (reusing the "Suggest improvements" diff styling).
- **Description + API endpoint on the prompts index.** Each prompt now shows its description and its API path with a copy button, right under the name.
- **Custom 400 and 422 error pages** in the standalone app, matching the existing 404/500 cards.

### Changed

- **On-brand flash & error callouts.** Notice/alert messages are now a mono uppercase status tag with a glowing dot in a faint tinted box — the same visual language as the worker-health banner — instead of a left-accent bar.
- **Models grouped by family/vendor everywhere, with a count.** The provider page's models table is sectioned by family (OpenAI: GPT-5, GPT-4, o-series, …) / upstream vendor (OpenRouter), the generation- and judge-model dropdowns group their options the same way, and the providers index shows how many models each credential has.
- **Refresh-models button disables and spins while discovery is running**, so a second discovery can't be kicked off mid-run.
- **Clearer prompt-form note** when editing a prompt that already has runs — it just says saving will create a new version; the misleading "publishing freezes the template" wording is gone (there's no separate publish step in the save flow).

## [0.5.5] - 2026-05-12

### Added

- **Opt-in "Load sample data" on the onboarding page.** A quiet, secondary button that seeds one starter dataset (`Sample: Customer tickets`) and one starter prompt (`Sample: Support reply`) so you can poke around without a blank slate. Shows only while neither a dataset nor a prompt exists; idempotent; never creates a provider credential or a run. Nothing is auto-seeded — a fresh install still reads 0/4.

### Changed

- **OpenRouter discovery is now metadata-driven and instant.** OpenRouter publishes capability metadata in its model list, so the engine derives capabilities from it instead of probing each of ~350 models with a live call (which took ~18 min). `supports_generation` now comes from `architecture.output_modalities` — fixing a bug where every OpenRouter model, including image-generation ones, was marked generation-capable. `supports_judging` stays **unknown ("?")** until a real run proves it; a successful judged review promotes the model to confirmed. Discovery skips probing for OpenRouter entirely.
- **Judge-capability is now a three-state.** `supports_judging` of `nil` means "untested" — rendered as `?` on the provider page's models table and `(?)` in judge pickers. Untested models are still selectable as judges (only models known to be bad judges are hidden), and the first successful run with one flips it to `✓`. Runtime judge failures stay graceful: a flaky judge fails just that row's review, the run carries on, and a single failure never demotes the model.

## [0.5.4] - 2026-05-12

### Added

- **Onboarding checklist at the engine root.** A fresh install now lands on a setup checklist — connect a provider → upload a dataset → write a prompt → run it — with progress tracking, a highlighted "next up" step, and per-step "done" state derived from whether those records exist. Once all four are present (or you click "Skip setup"), the root redirects straight to Prompts. Re-open it any time from **Settings → Getting started**. Dismissal is a cookie — no schema, host-app-agnostic. No auto-seeded data.

### Fixed

- **Suggest improvements ✨ icon sizing/color.** The `sparkles` heroicon added in 0.5.3 fell back to the 24px outline variant and ballooned to fill the button; it's now sized to the label (`1.1em`) and stroked in `--ck-warning` gold via a `.ck-magic-icon` class. `.ck-button` also gained `white-space: nowrap` so labels stop wrapping.

## [0.5.3] - 2026-05-10

### Changed

- **Sparkles ✨ icon on Suggest improvements buttons.** The "Suggest improvements" action on `runs/show` and `prompts/show` now renders a `sparkles` heroicon ahead of the label — same convention as other "AI magic" affordances in modern UI.
- **`.ck-button` icon-text spacing baked in.** Added `gap: 0.4rem` to the base button. Future icon+text buttons no longer need per-button rules.

## [0.5.2] - 2026-05-10

### Changed

- **Terminal job failures now report to `Rails.error`.** `GenerateRowJob` and `JudgeReviewJob` send their `rescue_from(StandardError)` failures through `Rails.error.report(error, handled: true, context: { ... })` before recording the terminal failure on the row/review. Any registered error subscriber (Sentry, custom logger, etc.) will pick these up automatically; no opt-in or configuration required. No behavior change for hosts with no subscribers.

## [0.5.1] - 2026-05-10

### Changed

- **Layout JavaScript externalized into an asset.** Behaviour-critical JS that previously lived inline in the engine layout (live tag-breadcrumb updates, `[data-local-time]` formatting, relative-time ticking, CSV row hover-expand, model-refresh progress, focus-first-error) now ships as `completion_kit/application.js`. Host apps that override the engine layout must add `<%= javascript_include_tag "completion_kit/application", defer: true %>` alongside the existing stylesheet include — without it, those behaviours silently fail.

### Fixed

- **Tag breadcrumb live update** — Rails `form_with` doesn't auto-generate `id` attributes; the input listener was matching against `id="tag_name"` which was never rendered. The form now sets the id explicitly, and a request-spec assertion guards against future regressions.

## [0.5.0] - 2026-05-09

### Added

- **Tags** — Polymorphic domain tags for metrics, prompts, runs, datasets, and metric groups with a 10-color auto-assigned palette. Filter each index page by tag (`?tag[]=...` URL params, OR semantics across multiple selected tags). Tag CRUD via web UI (`/tags` under Settings), REST API (`/api/v1/tags`), and MCP tools (`tags_list`, `tags_get`, `tags_create`, `tags_update`, `tags_delete`). All taggable resources accept a `tag_names: [...]` field on their existing create/update endpoints with auto-create + replace semantics.
- **In-form tag filter for metric selection** — runs form and metric_group form let you narrow the visible metrics by their tags before checking which ones to apply.
- **Settings dropdown** — top-nav `Settings ▾` consolidates `Providers` and `Tags` (porting the `<details>`-based menu pattern from completion-kit-cloud).
- **Site-wide cascade-aware delete confirmations** — every edit form's trash button shows a count of what gets deleted (e.g. "Delete 'X'? Cascades through 3 runs and 75 responses (and their reviews)").
- **Autofocus on form errors and `/new` pages** — site-wide `turbo:load` handler focuses the first invalid field when validation fails, or the first field on a fresh `/new` page.

### Changed

- **Dataset deletion now cascades to runs** (was `restrict_with_error`) — mirrors `Prompt.has_many :runs, dependent: :destroy`.
- **bin/dev** in `standalone/` now actually launches `Procfile.dev` (web + worker) via foreman instead of just `bin/rails server`.
- **Customer-support seed data** — replaces the property-listings demo with three retail prompts (Support Reply Generator, Ticket Triage, Ticket Summary), 9 scoped metrics across three Reply/Triage/Summary metric groups, 15 scored responses, and tag wiring across `customer-support`, `reply`, `triage`, `summary`.

## [0.4.8] - 2026-05-07

### Changed

- **Ruby upgraded to 3.4.5** — `.ruby-version` at the repo root and
  in `standalone/`, plus the `ruby` directive in `standalone/Gemfile`
  bumped to match. Required for the security-bumped nokogiri 1.19.3
  and net-imap 0.6.4, both of which need Ruby ≥ 3.2.

## [0.4.7] - 2026-05-07

### Security

- **nokogiri 1.19.2 → 1.19.3** — fixes high-severity CSS selector
  tokenizer regex backtracking ([CVE](https://github.com/sparklemotion/nokogiri/security/advisories))
  and medium-severity XSLT memory leaks. Picked up by the engine
  Gemfile.lock and the standalone Gemfile.lock.
- **net-imap 0.6.3 → 0.6.4** — fixes high-severity STARTTLS stripping
  via invalid response timing, plus medium-severity command injection
  paths via raw arguments / unvalidated Symbol inputs / DoS via SCRAM
  iteration counts, and low-severity quadratic-complexity literal
  reads.

## [0.4.6] - 2026-05-07

### Changed

- **Dataset preview modal flattened** — single background tone (no
  cyan-gradient header, no separate footer surface), header padding
  tightened so the table sits closer to the title, redundant footer
  Close button removed (× at top is enough), title + row count inline
  on one row.
- **Modal close button rebuilt** — borderless circle that lights up on
  hover, × symbol forced into proper centering with `inline-flex` +
  `padding: 0` + sans-family override (the symbol rendered offset in
  the mono font), default focus outline replaced with a controlled
  `:focus-visible` ring that wraps the symmetric circle.
- **CSV row expand-on-hover smoothed** — uses a 350ms hover delay so
  quick scrolling no longer triggers expansion, then animates the
  expansion with a 300ms eased `max-height` transition. Cell content
  wrapped in `<span class="ck-csv-cell">` with `-webkit-line-clamp: 1`
  for the collapsed state.
- **Native cell tooltips removed** from the CSV preview — the inline
  expand reveals the full content; the browser's `title` tooltip on top
  was redundant noise.
- **Modal scroll handling** — the dataset preview's CSV wrap no longer
  caps its own height; the modal body's existing `overflow: auto`
  handles internal scrolling once content exceeds the panel's
  `max-height: 82vh`.

### Fixed

- **Provider page judges count was misleading** — it counted every Run
  using this provider as judge (including duplicates). Now counts
  distinct `judge_model` values, which matches the natural reading of
  "X judges" (parallel to "X prompts").

## [0.4.5] - 2026-05-07

### Added

- **Live status panel during runs.** The completed-run summary layout
  (Outcome / Metrics / Avg score) now also drives the running view, with
  per-row updates broadcast on every Generate and Judge job completion.
  Metric pip bar shows one pip per configured metric — colored as soon
  as any reviews score, dim "pending" otherwise. Avg score badge
  appears as a running average the moment any reviews come in. Outcome
  reads `3 of 5 responses · 1 of 5 judged` while in flight.
- **Status pill inside the panel.** Small color-coded `● RUNNING` /
  `● COMPLETED` indicator beside the Outcome label so the run state is
  visible without scrolling back to the page header.
- **Re-run-temperature awareness.** New `temperature_ignored:boolean`
  column on runs. Each LLM client (Anthropic, OpenAI, OpenRouter,
  Ollama) now exposes `temperature_dropped?` after a call and the
  GenerateRowJob persists the flag to the run when the fallback fires.
  Run show page renders a small "ignored by model" caption next to the
  temperature value when set. Migration `20260507150000`.
- **Stricter generation probe.** Sends `Reply with exactly this token
  and nothing else: PING-OK` and only marks `supports_generation = true`
  when the response actually contains `PING-OK`. Image-only models that
  reply with refusal text (e.g. *"I am an image generation model..."*)
  now correctly fail the probe with a clear error rather than being
  classified as text generators.
- **Re-run feature**: `POST /runs/:id/rerun` clones a run's config
  (prompt, dataset, judge model, temperature, metrics) and starts it.
  Surfaces as a "Re-run" button on completed runs and
  "Re-run as new" on failed runs.
- **Per-response status column** with explicit Done / Judging / Awaiting
  judge / Queued / Generating / Retrying chips. New
  `Response#fully_reviewed?` checks every configured metric has a
  terminal review for that response — eliminates the previous bug where
  "Done" lit up after the first metric scored.
- **Per-response metric pip bar** in the responses table, sorted
  alphabetically.
- **Compact relative-time** as the default for `<time
  data-relative-time>` — renders `5m`, `2h`, `21d`, etc. Verbose
  available via `data-relative-time="verbose"`.
- **Dataset CSV preview** rendered as a sortable HTML table with sticky
  header, row-number gutter, ellipsis-truncated cells, and hover-to-
  expand. Fallback to raw `<pre>` if CSV parsing fails.
- **Best score column on prompts index**, scoped to the row's current
  version. Empty `—` when no completed runs.
- **Worker health check tightened** to require a `Worker`-kind process
  with a fresh heartbeat (was: any SolidQueue process). Run page
  re-fetches the status header ~1s after load to clear false-positive
  banners caused by transient worker restarts. Banner restyled as a
  warning with a structured title + body.

### Changed

- **Runs table consolidated to one shared `_row` partial** used across
  runs/index, prompts/show, and datasets/show. Columns harmonized to
  Run | Prompt | Responses | Metrics | Avg score | When (with the
  Prompt cell stacking dataset name + count on a sub-line).
- **Responses table redesigned as a `ck-results-table`** with columns
  # | Response | Metrics | Avg score | Status. Score uses the colored
  `ck-badge` pill matching every other table.
- **Prompts index columns**: Name | Version | Model | Best score |
  Runs (with last-run timestamp as a sub-line). Drops the standalone
  Last run column whose visual prominence outweighed its information
  value.
- **Run-name dot is now bigger and more legible** — 10×10 with a soft
  colored glow, so status reads at a glance across long lists.
- **Stars unified to gold** (`var(--ck-warning)`) everywhere; SVG
  stars on metric forms / show / response detail were previously cyan.
- **Metric form fonts**: metric names and group pill labels switched
  to mono so they read as identifiers, with sans body for instruction
  copy. Custom dark-themed checkboxes already in place.
- **Metrics index "In groups" column** renders each membership as a
  cyan pill (link to the group), matching the run-form group toggles
  but without the tick (membership, not selection).
- **Status panel sort toolbar reserves its slot** so the buttons
  appearing after a run completes no longer kicks the response table
  down by ~3rem.
- **Field hint slot reserves space** (`min-height` on
  `.ck-field-hint`) — toggling judge / dataset / metrics hints in and
  out no longer shifts the run form.
- **Page no longer jumps right when a scrollbar appears** — added
  `scrollbar-gutter: stable` on `<html>`.
- **Datasets index Created column** uses a readable absolute date
  (`Apr 16, 2026`) instead of a relative one.
- **Prompt versions Created column** includes the time
  (`Apr 16, 2026 at 3:31 PM`) for debugging.
- **Worker-down banner copy** restructured as a structured warning
  (title + body) using amber rather than red — jobs aren't lost, just
  queued.

### Fixed

- **Provider page judges count was misleading.** It counted every Run
  using this provider as judge (including duplicates) but the label
  read "X judges" — implying distinct judges. Switched to count
  distinct `judge_model` values: now matches the natural reading.
- **Dataset preview modal on the run page** uses the same
  `ck-csv-table` styling as the dataset show page (sticky header,
  row-number gutter, ellipsis cells) instead of a raw `<pre>` text
  dump. CSV table inside the modal is borderless to avoid a box-in-a-
  box look.
- **CSV table cells no longer expand on hover** — that was causing the
  rest of the page to shift up/down as you moved between rows. Cells
  stay fixed-height with ellipsis truncation and use a native `title`
  tooltip to show the full content on hover.
- **OpenRouter requests were silently 404ing.** `OpenRouterClient`'s
  Faraday base URL was `https://openrouter.ai/api/v1` and request URL
  was `/chat/completions` — Faraday strips the base path when the
  request URL has a leading `/`, so every POST went to
  `https://openrouter.ai/chat/completions` (the marketing site,
  returning HTML). Fixed by moving the prefix into the request URL.
- **`GenerateRowJob` now marks `Error: …` LLM responses as failed**
  instead of stuffing the rescue string into `response_text` and
  marking succeeded.
- **Run show page no longer hides "Error:"-text rows** — removed the
  `valid_responses` filter that swallowed stale historical rows.
- **OpenAI `extract_text` finds the message item** in the reasoning-
  model output array instead of reading `output[0]` blindly.
- **Job tests stub `broadcast_progress`** to allow the new live
  per-row panel updates without rendering partials in the test
  environment.

### Schema

- **`completion_kit_runs.temperature_ignored: boolean default false`**
  — set by the job when the LLM client falls back to retrying without
  the temperature parameter.

## [0.4.4] - 2026-05-07

### Added

- **Re-run a run as a sibling.** New `POST /runs/:id/rerun` member action
  clones the source run's prompt, dataset, judge model, temperature, and
  metric_ids into a fresh run and immediately calls `start!`. Surfaces as
  a "Re-run" button on completed runs and "Re-run as new" on failed runs
  (alongside the existing in-place "Retry"). The original run is
  preserved as history.
- **Per-response metric pip bars** in the responses list, matching the
  pattern used in the prompts/show runs table. Each succeeded + reviewed
  row shows one colored pip per metric review (sorted alphabetically by
  metric name) with the metric name and score in the hover label.
- **Status column on the responses table** with a vocabulary that
  matches the row's actual state: Queued / Generating / Retrying N/5 /
  Judging / Awaiting judge / Done (green) / Retry button. The chip is
  always present so the column never reads as empty.
- **Updated temperature hint copy** on the run form to mention that
  newer reasoning-class models (Claude Opus 4.7, GPT-5 family) ignore
  temperature and CompletionKit re-sends without it.

### Changed

- **Responses list redesigned as a `ck-results-table`** to match the
  runs/prompts/suggestions tables. Columns: # | Response | Metrics |
  Score | Status | →. Score column uses the same `ck-badge` pill (green
  / amber / red) as the runs table — the previous star+number widget is
  gone. Failed rows surface their provider error inline in red. Status
  column is the rightmost data cell so the hierarchy reads
  content-first, state-last.
- **Star icons now render gold** (`var(--ck-warning)`) everywhere. The
  SVG stars on metric rubric forms, metric show pages, and response
  detail pages were previously cyan, while the legacy text-glyph star
  was gold — inconsistent. Unified on the warmer color so stars read as
  rating semantics, not as accent navigation.
- **Suggestion show page meta line uses the colored score badge**
  (`ck-badge`) instead of plaintext "4.13/5", matching how scores read
  everywhere else.
- **Runs table on the prompt show page** drops the redundant Version
  column (the run name already carries the version, e.g. "Property
  Summary — v5 #2"). Metrics column moved to the left of Avg score so
  the "what was measured" reads before "how well it did".

### Fixed

- **OpenRouter requests were 404ing silently.** `OpenRouterClient`'s
  base URL was `https://openrouter.ai/api/v1` and the request URL was
  `/chat/completions`. Faraday treats a leading `/` as an absolute path
  relative to host and **strips the base path**, so every POST went to
  `https://openrouter.ai/chat/completions` — which returns the
  marketing site's `<!DOCTYPE` HTML. Every OpenRouter run since the
  client shipped failed JSON parsing and stored the error text as the
  response. Fixed by moving the `/api/v1` prefix into the request URL,
  matching the (correct) probe code in `model_discovery_service.rb`.
- **`GenerateRowJob` now treats `Error: …` text from the LLM client as
  a real failure** instead of stuffing the error string into
  `response_text` and marking `succeeded`. Raising forces the
  rescue_from path so the response is correctly flagged `failed` with
  the parse error in `error_message`. Per-row Retry and bulk "Retry N
  failed rows" both now work on these.
- **Stale "Error: …" responses are no longer hidden by the show view.**
  Removed the `valid_responses` filter that swallowed any row whose
  text started with `Error:`, leaving the user with a "5/5 succeeded"
  status panel and zero visible rows.
- **Dataset hint info color is cyan, not orange.** Reserved orange for
  actual warnings; informational guidance ("Select a dataset to provide
  values") now uses `ck-field--info`.
- **Run page no longer shifts vertically** when judge / dataset hints
  toggle — `.ck-field-hint` reserves a `min-height` slot, and the
  dataset hint+mismatch elements collapsed into one shared slot.

## [0.4.3] - 2026-05-07

### Added

- **Suggestions are now a real resource.** `GET /suggestions/:id` and
  `POST /suggestions/:id/apply` replace the run-scoped `runs#suggestion` /
  `runs#apply_suggestion` actions. Clicking a row in the suggestions table
  on a prompt page now opens the specific suggestion you clicked, not "the
  latest suggestion for that run". Breadcrumbs adapt via `?from=run` /
  `?from=prompt`: arrive from a run page and you get `Runs > [run] >
  Suggestion` with a "Back to run" button; arrive from the prompt page and
  you get `Prompts > [prompt] > Suggestion` with "Back to prompt".
- **Run form now hard-blocks variable mismatches.** A `Run` validation
  rejects saves where the prompt's `{{vars}}` aren't all present in the
  selected dataset's CSV headers (or no dataset is selected when the prompt
  needs one). Client-side, the dataset field paints red and lists the
  missing columns live as you change the prompt or dataset; submit is
  disabled until the mismatch is resolved.
- **Worker-down banner now self-refreshes.** A new
  `GET runs/:id/refresh_status.turbo_stream` endpoint plus a 15-second JS
  poll on the run show page re-renders `#run_status_header` while the run
  is `pending` or `running`. Previously, if a worker died after a run
  started but the heartbeat was still inside the 30s window, the banner
  would never appear without a manual reload.
- **Provider key failures now surface as discovery errors.**
  `ModelDiscoveryService` raises a typed `DiscoveryError` on any non-success
  response from the model-list endpoint (with friendly labels — "Invalid
  API key for openai", "Rate limited by anthropic", etc. — plus the
  provider's own error message). The `ModelDiscoveryJob` persists the
  message into a new `discovery_error` text column, and the discovery
  status bar shows it inline. Previously, a bad key silently retired every
  existing model and stamped the status as `completed`.
- **Auto-updating relative timestamps.** Every "X ago" cell on the prompts
  index, prompt show (versions / runs / suggestions tables), provider
  credentials index, and discovery status bar is now wrapped in
  `<time data-relative-time>`. The layout's 30-second JS ticker rewrites
  the text in place so "1 hour ago" becomes "2 hours ago" without a page
  reload. The relative-time helper output is normalised so the surrounding
  " ago" text doesn't double up after a tick.
- **Version column on the prompts index.** Pulled the version chip out of
  the Name cell into its own column. Shows "of N" only when the displayed
  version isn't the latest in the family.
- **Variable validation: `Run#missing_dataset_variables`** returns the list
  of unmet variables as a public method, plus `Dataset#headers` parses the
  first CSV line into a column list.

### Changed

- **Run form: prompt selector enriched.** Option labels now read
  `Property Summary — v5 · gpt-5 · 2 vars` (model + variable count), and
  selecting a prompt reveals a small summary card below with the prompt's
  description and a 220-char template preview. The dataset row in the
  run-config metadata table on the run page now carries the row count and
  a "Preview" pill that opens the dataset modal — replacing the standalone
  trigger card that floated below the table.
- **Metrics field redesign.** Replaced the inline "Quick add: CHIP CHIP"
  shortcut row with a labeled `Groups` row of pill toggles (sentence-case,
  with checkmark + member count). Click a group to add all its metrics;
  click again to clear. The pill highlights cyan when all its members are
  checked, so you can tell at a glance which group your selection
  matches. Custom dark-themed checkboxes replace the default white-square
  inputs. Metrics now lay out in an auto-grid (3+ columns on wide screens,
  1 on narrow) and each entry shows its `instruction` text (truncated to
  90 chars) underneath the name so terse names like "Accuracy" get
  context.
- **Judge model field gains a help icon.** Reuses the same copy as the
  models card: "Judge models score generated responses against your
  metrics. Pick one when configuring a run."
- **Unified `?` info-icon styling.** The base `.ck-info-toggle` now bakes
  in font-family sans, no letter-spacing, no text-transform, line-height
  1, and 16x16 size — so the question-mark renders identically inside an
  uppercase letter-spaced label, a table header, or anywhere else. The
  model-table-specific override is reduced to a single `top: -1px`
  baseline nudge.
- **Dataset hint behaves like the other "do this to proceed" hints** —
  cyan `ck-field--info` instead of warning-orange when guidance is just
  informational. Reserved for actual problems: dataset/header mismatch
  uses `ck-field--error` (red).
- **Field hint slots reserve their space** (`min-height` on
  `.ck-field-hint`), so toggling judge/dataset/metrics hint text in and
  out no longer shifts the rest of the page vertically. The two
  mutually-exclusive dataset hints (`#dataset-hint`,
  `#dataset-mismatch`) collapsed into one slot.
- **Run-name dot now sits inline with the text** (`gap: 0.6rem`) instead
  of being absolutely positioned at `left: -1rem`, which threw it outside
  the table cell entirely.
- **Suggestions table cells no longer wrap mid-content.** Run-name
  column and any time-cell get `white-space: nowrap` plus `width: 1%` so
  the Reasoning column absorbs the slack and the em-dash / "X days ago"
  no longer break across multiple lines.
- **Suggestion show page kicker dropped its decorative dot.** The
  `ck-dot` class is reserved for actual status indicators (run state,
  score buckets); using it as kicker decoration implied a status that
  didn't exist.

### Fixed

- **`runs#refresh_status` route added** under `before_action :set_run` so
  the polling endpoint correctly loads the run.
- **Bad provider keys no longer wipe the model list.** `reconcile([])`
  used to fire after a silent fetch failure, retiring every existing
  model. The new typed exception bypasses reconcile entirely, so the
  prior model list is preserved while the error surfaces in the UI.
- **`Dataset#headers` is malformed-CSV safe.** Returns `[]` rather than
  raising on truncated/quoted-malformed first lines.
- **Suggestion link from prompts/show used to redirect to "the latest
  suggestion for that run"**, regardless of which row you clicked.
  Resolved by routing to `/suggestions/:id` directly.

### Schema

- **`completion_kit_provider_credentials.discovery_error: text`** —
  stores the human-readable error message from the most recent failed
  discovery run. Migration `20260507000001`.

### Provider client robustness

- **All four LLM clients (Anthropic, OpenAI, OpenRouter, Ollama) now
  retry once without `temperature`** if the model rejects it with a 400
  containing "deprecated", "not supported", or "Unsupported parameter".
  This was breaking runs against newer reasoning-class models — Claude
  Opus 4.7 returns `temperature is deprecated for this model.`, OpenAI
  reasoning models return `Unsupported parameter`. Detection is
  body-string based so it covers OpenRouter passing the upstream error
  through verbatim.
- **OpenAI client now finds the `message` item in the Responses output
  array** instead of reading `output[0]` blindly. Same fix as the model
  discovery probe — reasoning models put a `reasoning` chunk first, so
  the message lived at `output[1]` (or later) and the live client was
  returning nil/empty.

## [0.4.2] - 2026-05-06

### Added

- **Provider page: structured available-models table.** Each model is a row
  with the name, a green ✓ for generation support, and a green ✓ for judging
  support. Replaces the previous chip-cluster which made it hard to scan
  capabilities. Collapsed by default; auto-expands during a refresh and for
  about a minute after one completes. Header has hover-tooltips on the Gen
  and Judge columns explaining what they mean.
- **Live-updating models table during discovery.** As each model finishes
  probing, the table re-renders in place via Turbo Streams + morph (so the
  spinning refresh button keeps animating across renders). Refresh button
  spins and disables itself while a refresh is running.
- **Worker code auto-reload in development.** `bin/jobs` now wraps each job
  execution in `Rails.application.reloader` instead of the bare executor, so
  changes to job/service code are picked up without restarting the worker.
  Production keeps the lighter `Rails.application.executor`.
- **Smarter model re-probing.** Models that previously failed with a 4xx
  error other than 429 (e.g., a `tts-1` returning "You can't sample from
  this model") are no longer re-probed on every refresh. Models that failed
  with transient errors (5xx, timeouts, "Empty response", 429) ARE re-probed.
  Newly-discovered models are always probed once.
- **Per-row Retry on failed responses.** Failed rows in a run now have a
  `Retry` button on the right, scoped to just that row, alongside the
  bulk "Retry N failed rows" button in the run status panel.

### Changed

- **Run page status redesign.** Status indicator promoted to a proper
  colored pill in the page header (`● COMPLETED`, `● RUNNING`, etc.) with
  glow + animation matching the state. Generation/judging counters and the
  bulk retry button moved to a dedicated status panel above the responses
  list, styled as an instrument-panel strip.
- **Judged counters now track fully-reviewed rows**, not individual metric
  reviews. So `Judged 3/100` reads as "3 rows fully scored" instead of "3
  metric reviews complete (which might be 1 row of 3 metrics)". A row counts
  as `judged_failed` if any of its metric reviews failed.
- **Response detail page metadata uses the same config-table layout as the
  run page.** Run, Prompt, Dataset, Model, Judge as labeled rows instead of
  the inline `PROMPT … · DATASET …` line.
- **OpenAI probes now find the message item in the Responses output array.**
  Reasoning models (gpt-5*, o1*, o3*) return multi-item output where the
  first item is a `reasoning` chunk and the message comes later. The probe
  used to read `output[0].content[0].text` blindly and got nil for all
  reasoning models. Now it does `output.find { |o| o["type"] == "message" }`.
  This was the root cause of GPT-5.5 / GPT-5.5 Pro never being eligible as
  judges.
- **OpenAI probes use minimal/low reasoning effort when supported**, with a
  fallback to the model's default when the chosen effort isn't accepted
  (e.g., `gpt-5.5-pro` only allows `medium`/`high`). Probe budget bumped to
  65536 tokens and timeout to 180s for reasoning-class models.
- **OpenRouter and Ollama models now get judging-probed** via their
  OpenAI-compatible `/chat/completions` endpoints. Previously the probe
  router fell through to Anthropic's `/v1/messages` endpoint, so all
  OpenRouter and Ollama models were silently invisible as judges.
- **Auto-rename when saving as a new run.** If you edit a run with responses
  and don't change the name, the new run gets the next-incremented name
  (`#2`, `#3`, …) instead of inheriting the source run's name verbatim.
- **Engine routes are eagerly materialized before broadcast renders.** The
  worker process never serves an HTTP request, so Rails 8's lazy route set
  hadn't materialized engine URL helpers, causing `run_response_path`
  lookups to fail when a job called `broadcast_replace_to`. Touching
  `CompletionKit::Engine.routes.url_helpers` before render fixes it.
- **`Run#start!` writes a fresh `failure_summary`** on configuration errors
  ("LLM API not configured: …") and dataset-empty errors instead of only
  `error_message`, so the run page surfaces the right copy.
- **"Testing models" renamed to "Checking models"** in the discovery bar.
  "Fetching model list" renamed to "Looking up models". Friendlier wording.
- **Models card refresh button consolidated to one.** The previous version
  had duplicate refresh buttons (one in the form-card header, one in the
  disclosure summary). Now there's a single button next to the timestamp.
- **Provider edit page: discovery progress bar moved inside the Available
  models panel** instead of sitting above it, so the panel reads as a
  single coherent unit.

### Fixed

- **Worker process Turbo broadcasts could fail with `undefined method
  'run_response_path'`** when rendering response_row partials from a job
  context. Fixed by materializing engine URL helpers before each render.
- **Refresh button animation was lost on every Turbo Stream re-render** of
  the models card. Fixed by switching the broadcast from `replace` to
  `morph`, which preserves DOM identity and lets the CSS animation continue.
- **Per-row Retry button on failed responses was rendering on its own line
  beneath the row** because `<button_to>` was nested inside `<link_to>`
  (form-inside-anchor — invalid HTML, browsers hoist it out). Failed rows no
  longer wrap in `link_to`; they're plain `<div>` containers with the Retry
  button in the right column.
- **Available models help-text tooltip inherited the surrounding uppercase
  letter-spaced styling.** `.ck-info-popup` now explicitly resets
  `text-transform`, `letter-spacing`, `font-family`, `font-weight`, and
  `text-align` so help text always reads as normal sentence case.
- **Refresh on the provider page closed the available-models panel** because
  the re-rendered partial defaulted to collapsed. Panel now stays open while
  `discovery_status == "discovering"` and for 1 minute after `completed`.

## [0.4.1] - 2026-05-05

### Fixed

- **Live UI updates were broken on the run show page in 0.4.0.** The standalone
  shipped with `cable.yml` set to the `:async` ActionCable adapter, which only
  delivers messages within the same process. Once 0.4.0 moved generate/judge
  jobs into a separate `bin/jobs` worker process, the broadcasts those jobs
  emit became invisible to browser subscribers connected to the web process —
  the page would show pending rows forever even though the worker was
  successfully processing them. Adds `solid_cable` to the standalone's
  Gemfile, configures `cable.yml` to use it in development and production,
  and ships a migration for the `solid_cable_messages` table. After
  upgrading: `cd standalone && bundle install && bin/rails db:migrate`.

## [0.4.0] - 2026-05-05

### Added

- Per-row prompt-run jobs (`GenerateRowJob`, `JudgeReviewJob`) with independent
  retry on transient LLM failures (`Faraday::TimeoutError`,
  `Faraday::ConnectionFailed`, polynomial backoff) and rate limits
  (`CompletionKit::RateLimitError`, fixed 30s × N backoff). One bad row no
  longer kills the whole run.
- Generation and judging interleave automatically: each successful row
  enqueues its `JudgeReviewJob`s immediately rather than waiting for the
  whole batch.
- `Run#progress_snapshot` returns six counters (`generated_done/total/failed`,
  `judged_done/total/failed`); status header surfaces both.
- `POST /runs/:id/retry_failures` (web + `/api/v1/runs/:id/retry_failures`)
  re-enqueues only failed rows. Per-row Retry button on each failed response.
- Per-row provider error context: failed rows show
  `Failed: OpenAI 429 — Rate limit exceeded` so users can tell when a failure
  is the provider's fault, not CompletionKit's.
- New error classes: `CompletionKit::Error`, `CompletionKit::ConfigurationError`,
  `CompletionKit::RateLimitError(provider:, status:, retry_after:)`.
- All four LLM clients (`OpenAiClient`, `AnthropicClient`, `OllamaClient`,
  `OpenRouterClient`) raise `RateLimitError` on 429 and re-raise
  `Faraday::Error` so retries actually fire.
- `ModelDiscoveryJob` hardened with the same retry policy.
- `CompletionKit::WorkerHealth.healthy?` and a banner on running runs when
  no Solid Queue worker has heartbeated in 30s.
- `mission_control-jobs` dashboard mounts at `/jobs` in the standalone behind
  session auth.
- `Run#as_json` extended with `progress` object (`generated`/`judged`
  sub-objects with `done/total/failed`), `failed_response_ids`, and
  `failure_summary`. Legacy `progress_current` and `progress_total` keys
  preserved.
- `failure_summary` (text) on runs for infra-level failures (dataset empty,
  judge model unconfigured).
- `attempts`, `error_provider`, `error_class`, `error_status`, `error_message`,
  `row_index` columns on responses; same error/`attempts` shape on reviews.
- Compound indexes `[run_id, status]` on responses and `[response_id, status]`
  on reviews (created with `algorithm: :concurrently` on Postgres).

### Changed

- **Standalone deployment now requires a worker process.** The standalone
  switches from `:async` to `:solid_queue` for ActiveJob. Run
  `cd standalone && bin/jobs` alongside `bin/rails server` (or
  `foreman start -f Procfile.dev`). Without it, generate/judge runs sit at
  "running" forever — the new worker-health banner detects this.
- `Run::STATUSES` collapsed from `pending|generating|judging|completed|failed`
  to `pending|running|completed|failed`. Generation and judging now
  interleave so the separate phases stop making sense. Existing
  `generating`/`judging` rows are migrated to `running`.
- `Review::STATUSES`: `evaluated` renamed to `succeeded` for cross-model
  consistency. Existing rows backfilled.
- The standalone DB pool is sized dynamically to fit Solid Queue's thread
  count (`pool: max(RAILS_MAX_THREADS, SOLID_QUEUE_THREADS + 2)`).
- The MCP `runs_judge` tool is removed — judging is now per-row automatic.
  Tool count: 35 → 34.

### Removed

- `Run#judge_responses!` and the standalone `judge` controller actions
  (web + API). The new per-row job topology supersedes them.
- The legacy monolithic `GenerateJob` and `JudgeJob`. Use `Run#start!` (which
  enqueues `GenerateRowJob` per row) and let judging chain automatically.

### New environment variables (standalone)

- `SOLID_QUEUE_THREADS` (default 10) — worker thread pool size.
- `SOLID_QUEUE_PROCESSES` (default 1) — worker process count.
- `COMPLETION_KIT_LLM_CONCURRENCY` (default 10) — soft global cap on
  simultaneous LLM calls; warns at boot if set higher than
  `SOLID_QUEUE_THREADS`.
- `COMPLETION_KIT_PER_RUN_CONCURRENCY` (default 5) — max simultaneous LLM
  calls from a single run.

### Migration notes

- `bin/rails db:migrate` applies five new migrations (responses error
  columns + concurrent index; reviews error columns + concurrent index;
  runs `failure_summary`).
- A one-time `completion_kit:mark_interrupted_runs_failed` rake task is
  available if you have runs in flight at the adapter cutover. Most
  installations won't need it.

## [0.3.0] - 2026-04-25

### Changed

- **License:** CompletionKit 0.3.0 and later are licensed under the Business
  Source License 1.1 with a 3-year Change Date to GPL v3. You may use
  CompletionKit freely for any purpose — including production — except to
  offer it to third parties as a hosted or managed service whose primary
  value is CompletionKit itself. Versions 0.2.x and earlier remain
  MIT-licensed and are unaffected; anyone relying on MIT can pin to 0.2.x.
  See `LICENSE` for full terms and the Additional Use Grant.

### Fixed

- Includes the migration idempotency fix from 0.2.1.

## [0.2.0] - 2026-04-22

### Added

- Optional `tenant_scope` / `tenant_scope_columns` config hooks for multi-tenant host apps. No behavior change when unset.

## [0.1.0] - 2026-04-18

### Changed

- **Breaking:** `Criteria` renamed to `Metric Group` across the entire product.
  REST API paths `/api/v1/criteria` → `/api/v1/metric_groups`. MCP tools
  `criteria_*` → `metric_groups_*`. Ruby class `CompletionKit::Criteria` →
  `CompletionKit::MetricGroup`, `CompletionKit::CriteriaMembership` →
  `CompletionKit::MetricGroupMembership`. Web routes `/completion_kit/criteria` →
  `/completion_kit/metric_groups`. Database tables renamed in place; no
  data migration needed. No backwards-compatibility aliases.

### Removed

- **Breaking:** `evaluation_steps` column removed from the `Metric` model and
  all associated UI, REST API, and MCP tool surfaces. Scoring now relies on
  the metric's `instruction` and `rubric_bands` alone.

### Known limitations

- Standalone app uses the `:async` queue adapter (in-process only). Solid
  Queue migration is planned for 0.2.0.

## [0.1.0.rc1] - 2026-04-15

Release candidate 1 for 0.1.0. Published to RubyGems as
`completion-kit 0.1.0.rc1` for pre-release validation before cutting
the real 0.1.0.

Initial public release of CompletionKit, a Rails engine for testing and
evaluating GenAI prompts across multiple providers.

### Added

- **Prompts, Runs, Datasets, Metrics, and Criteria** — core models for
  defining prompts with variable placeholders, running them against CSV
  datasets, and scoring outputs with LLM judges against user-defined
  criteria.
- **Provider credentials** — encrypted storage for LLM API keys with
  auto-seeding from environment variables, masked display, and per-provider
  usage stats. Supports OpenAI, Anthropic, Ollama (or any OpenAI-compatible
  local endpoint), and OpenRouter.
- **Model discovery** — asynchronous fetching of available models per
  provider with real-time progress updates. OpenRouter and Ollama discovery
  trust the upstream API's model list and skip per-model probing, keeping
  discovery fast for providers that publish capability metadata.
- **REST JSON API** — Bearer token authenticated API exposing full CRUD
  for Prompts, Runs, Datasets, Metrics, Criteria, and ProviderCredentials;
  nested read-only Responses under Runs; and `POST /api/v1/runs/:id/generate`
  and `/judge` process actions that return `202 Accepted` for async
  processing.
- **MCP server** — 36 tools mirroring the REST API, exposing CompletionKit
  to agent clients via the Model Context Protocol. Install cards with
  one-click copy for Claude Code and other MCP-compatible clients.
- **Web UI** — session-based login, onboarding dashboard showing only
  remaining setup steps, prompt and run management, Turbo Stream live
  updates for run progress and response rows, and a progress bar partial.
  Model dropdowns are grouped by provider, with OpenRouter models split
  further by upstream namespace.
- **Background jobs** — `GenerateJob` and `JudgeJob` for async processing,
  with Solid Queue configured in the standalone app.
- **Suggestion history** — AI-assisted prompt improvement suggestions
  persisted to the database, tracked with applied status, and surfaced in
  the prompt UI for evolution history.
- **Temperature control** — per-run temperature slider with info tooltip
  (default 1.0).
- **Retry failed runs** — "Retry" action that only appears on failed runs.
- **Edit-as-new-run** — editing a run with existing responses creates a
  new run, preserving the original.
- **Judge input awareness** — judge is passed the input data so it can
  verify claims against the actual input, not just the output.
- **API reference page** — per-endpoint documentation with params,
  copy-to-clipboard examples, and MCP tab shown by default.
- **Standalone app** — bundled Rails app under `standalone/` for local
  development and self-hosting, with dotenv support and Active Record
  encryption for stored provider API keys.
- **CI/CD** — GitHub Actions workflow and Dependabot.
- **100% test coverage** — line and branch coverage enforced in CI across
  440+ RSpec examples.

[Unreleased]: https://github.com/homemade-software-inc/completion-kit/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/homemade-software-inc/completion-kit/compare/v0.1.0.rc1...v0.1.0
[0.1.0.rc1]: https://github.com/homemade-software-inc/completion-kit/releases/tag/v0.1.0.rc1
