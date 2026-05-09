# Changelog

All notable changes to CompletionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Tags** — Polymorphic domain tags for metrics, prompts, runs, and datasets with a 10-color auto-assigned palette. Filter each index page by tag (`?tag[]=...` URL params, OR semantics across multiple selected tags). Tag CRUD via web UI (`/tags`), REST API (`/api/v1/tags`), and MCP tools (`tags_list`, `tags_get`, `tags_create`, `tags_update`, `tags_delete`). The four taggable resources accept a `tag_names: [...]` field on their existing create/update endpoints with auto-create semantics — passing an unknown name silently creates the tag. Replace semantics on PATCH (passing `tag_names: ["foo"]` removes any tag not in the list).

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
