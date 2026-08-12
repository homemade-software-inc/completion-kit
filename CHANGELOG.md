# Changelog

All notable changes to CompletionKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.28.42] - 2026-08-11

### Changed
- **The four dashboard stat cards now line their numbers up with each other.** Each card pushed its value into the middle of whatever space was left over, so the value landed at a different height in every card depending on how much content sat below it. The Checks percentage came out 63 pixels above the Activity count in the card beside it. The value now sits directly under the kicker in all four, which puts the kickers on one line, the values on a second, and the footnotes on a third along the bottom, so the row reads across instead of bobbing.

## [0.28.41] - 2026-08-11

### Changed
- **A dashboard card with nothing to plot no longer draws an empty chart.** The Checks card and the Activity card both rendered all fourteen bars whatever the data, and a bar for a day with no data is held at a two-pixel minimum height, so a window with nothing in it came out as a row of dead dashes that reads as a broken chart rather than an absent one. Both cards now drop the sparkline entirely when the window is empty, leaving the headline and the footnote that says what to do about it. Days with no data inside a window that does have some are unaffected, because there the gap is real information.

## [0.28.40] - 2026-08-11

### Changed
- **The retry button on a run now says what it will actually retry, and it is no longer red.** It read "Retry N failed cases" whatever had gone wrong, which implied regeneration even when the response was fine and only its judge had timed out. The label is now chosen from the failure state: "Retry scoring on 1 response" when only reviews failed, "Retry 1 failed response" when only generation failed, and the combined count when both did. The button also drops its bespoke red styling for the same secondary outline used by Edit and Compare in the page header. Red now belongs to the parts of the panel that report state, the failed count in the summary line and the row chips, rather than to the action that clears them.

## [0.28.39] - 2026-08-11

### Fixed
- **"Retry failed cases" did nothing when the failure was a judge, and left the run stuck running.** A response can generate perfectly well and still have its review blow up, which the run header counts as a failed case. The retry only ever looked at responses whose own status was `failed`, so for a failed review it matched nothing, enqueued nothing, and still flipped the run to `running`. Since the completion check is only ever enqueued by a finishing job, that run then had no way back to `completed` and sat running forever. Retry now collects failed reviews on succeeded responses too and re-queues each against its own metric, judge or check, followed by a completion check. When there is genuinely nothing to retry it returns without touching the run's status.

- **A response whose judge failed claimed it was Done.** The row chip treated any review in a terminal state as reviewed, and a failed review is terminal, so the row read Done while the header counted the same response among the failed. The two now agree: a response with a failed review shows a Failed chip once the run has finished. The gap it leaves in the metric bar is expected, because a review that never produced a score has no score to draw.

## [0.28.38] - 2026-08-05

### Fixed
- **The two buttons on the stale-metrics banner were touching.** Each action column was capped at a fixed width chosen for its explanatory note, but a button never shrinks below its own text, so the wider "Re-grade with current metrics" overflowed its column by 26 pixels and closed the gap to the button beside it. Measured, the two buttons sat 3 pixels into each other. The column is now sized by the button rather than by the note, so the gap is the 1.25rem it was always meant to be and the note wraps underneath its own button. Checked at five widths from 1440 down to 520 pixels, where the pair wraps to a stack with the same spacing.

## [0.28.37] - 2026-08-04

### Changed
- **Temperature is no longer something you configure. Runs send none by default.** The parameter has aged out. Most current frontier models refuse it outright, several accept it and silently discard it, and the ones that still honour it are the previous generation and anything served locally, where sampling happens in your own process and no vendor API can say no. A knob that most models ignore is worse than no knob, because it invites you to believe you set something you did not.

  The generation temperature slider and the judge temperature field are both gone from the run form, and the run's `temperature` column now defaults to unset, so a new run sends no temperature at all and the model applies its own. This also settles a default that had drifted: the engine migration said 1.0 while installed copies said 0.7, and now both say nothing.

  **Nothing is removed from the API.** `temperature` and `judge_temperature` remain on the REST endpoints, the MCP tools and the run payload, so anything scripted against them keeps working, and anyone deliberately targeting a model that honours temperature can still set one. The drop-and-retry, the two ignored flags and the refusal warnings all remain, and they now do their real job: telling you a value you deliberately chose was refused.

  The run page mentions either temperature only when there is something to say. A run carrying a temperature still shows it, which keeps historical runs honest about what they sent, and the judge temperature row appears only when the scores are not reproducible.

  **Existing runs are untouched.** A column default change does not rewrite rows, so a run that sent 0.7 still records 0.7. Host apps need `bin/rails completion_kit:install:migrations && bin/rails db:migrate` to pick up the new default.

## [0.28.36] - 2026-08-04

Follow-ups to 0.28.35, all found by adversarially reviewing it after it shipped.

### Fixed
- **A list of the parameters a model does support is no longer read as a refusal.** OpenAI-compatible local servers answer with shapes like `unsupported parameter: logprobs. Supported: model, prompt, temperature, top_p`, where the word temperature appears because it is allowed, not because it was refused. The 0.28.35 predicate matched that, so the client burned a second call re-sending the same rejected request and could flag a run as having had its temperature ignored when the model had been perfectly happy with it. The phrase-first branch now stops at a comma, which is what separates a list from a sentence. The temperature-first branch still allows commas, because `temperature, top_p and top_k are not supported` is a real refusal.

- **A provider that names the offending field in `param` rather than in the message is now recognised.** A body reading `{"message":"This parameter is not supported with this model.","param":"temperature"}` matched nothing, so the row failed instead of retrying.

- **The run page no longer renders an empty temperature for a run that deliberately sends none.** It now reads "Not sent, provider default", matching how the Max tokens row two lines below already handles the same situation.

- **The judge-refusal chip appears without a reload.** The run config block was not among the poll's targets, so a run could finish judging and never tell the watching user that its temperature had been refused, which is the one thing the new flag exists to say. The block is now a partial the status poll refreshes alongside the header and the panel.

### Changed
- **The MCP `temperature` description documents what null now means.** An agent passing null to mean "use the default" would instead get no temperature sent at all, and nothing said so.

## [0.28.35] - 2026-08-04

### Fixed
- **A run whose judge silently lost its temperature no longer claims the scores are reproducible.** `JudgeService` sends the judge temperature and then nobody read whether the provider accepted it, so when a reasoning judge refused the parameter the request was quietly re-sent without one, the provider applied its own default of roughly 1.0, and the run went on reporting `judge_temperature: 0` with `nondeterministic_judge?` returning false. The page was at its most confident exactly when the scores were least reproducible. Runs gain a `judge_temperature_ignored` column, `JudgeReviewJob` records it, and `nondeterministic_judge?` folds it in. The run page and the MCP payload now distinguish a temperature you set high from one the model refused, because the fix for each is different.

  **Host apps need `bin/rails completion_kit:install:migrations && bin/rails db:migrate` to pick up the new column.**

- **Every provider client now recognises a temperature refusal it previously failed on.** All five tested the error body for `"not supported"`, `"deprecated"` or `"Unsupported parameter"`, but OpenAI's current reasoning models answer with `Unsupported value: 'temperature' does not support 0.7 with this model. Only the default (1) value is supported.`, which contains none of those three. The drop-and-retry never fired and the row failed outright. The predicate now covers the phrasings in use, in either word order, and it lives on `LlmClient` instead of being copy-pasted into five subclasses, which is how `AnthropicClient` came to be missing a clause the other four had.

  The match is deliberately bounded so it cannot cross a brace in the error body. A refusal aimed at some other parameter, in a response that echoes the request back, would otherwise have stripped a temperature the model was perfectly happy with and flagged the run as having had it ignored.

- **Both ignored flags now clear when the work they describe is redone.** Neither was ever reset, so a run kept asserting that its temperature had been refused after a re-grade against a judge that accepts it. `regrade!` clears the judge flag and starting a run clears both.

### Added
- **A run can now send no temperature at all, which is the only request many current models accept.** Every client turned a nil into 0.7, so there was no way to express "leave it to the model" and a nil column silently became a value CompletionKit invented. Passing an explicit nil now omits the parameter from the request body, and the run form gains a "Send no temperature" option beside the slider. An absent key still gets the historical default, so no existing caller changes.

### Changed
- **`temperature_ignored` is now in the run payload.** The MCP tool description told agents that "the run is flagged temperature_ignored" while `Run#as_json` never carried the field, so both REST and MCP pointed at something that did not exist. It and `judge_temperature_ignored` are now returned.

## [0.28.34] - 2026-08-04

This release also carries 0.28.33, which was versioned but never published. Its section is below in full; in short, a response scored only by deterministic checks no longer claims a judge reviewed it, a check that failed before its version was recorded is no longer blamed on the judge, and the gemspec's MCP tool count is corrected from 34 to the real 53. No migrations are needed for either version.

### Changed
- **The dashboard's Checks card no longer shows the same metric twice.** It listed the two most recent failing checks, and because failures cluster by metric, both rows routinely named the same one, so two lines carried a single fact and could only be told apart by hovering. The rows now group by metric and carry a count, so two lines say two things: which checks are failing and how badly. The total moved to the footer, which reports it once instead of as a remainder.

### Added
- **The seed demonstrates the deterministic check metric type, which it never did before.** A workspace seeded from scratch had no check metric at all, so the Checks card had nothing to show and the check type was invisible to anyone evaluating CompletionKit. Two checks now run alongside the existing LLM judge on the triage runs: `Rationale Length`, a `length_bounds` check reading `rationale` out of the JSON output, and `Triage Schema`, a `not_contains` check for a key the prompt never asked for. Both are evaluated through the real `Checks::Registry` and `TargetResolver` at seed time rather than hand-authored, so a seeded review is what the job would have written and a re-grade reproduces it.

  The result is the case the product exists for. On the triage rows the judge awards five stars and explicitly praises the extra `secondary` key, while the schema check fails the same response for emitting it, and on the bulk rows the judge scores a 2340-character "one-sentence rationale" at five stars while the length check fails it. The seeded data spreads across four days so the card's trend has shape, and the failures span two metrics and four runs so the card's two rows differ.

## [0.28.33] - 2026-08-03

### Fixed
- **A response scored only by deterministic checks no longer claims a judge reviewed it.** The review section on a response was headed "Judge's review" unconditionally, with a chip naming the run's judge model beside it, even when every review on the page was a pass/fail check that no LLM ever saw. The heading now follows the list: judge-only keeps "Judge's review" and the chip, check-only reads "Checks" with no chip, a mixed list reads "Judge's review and checks", and a list nothing can classify falls back to "Reviews". Heading and chip are derived from the same pair of booleans, so they cannot disagree with each other.

- **A check that failed before its version was recorded is no longer blamed on the judge.** `Review#check?` read only `metric_version`, but `CheckReviewJob` writes a terminally failed review without one, so such a review classified as a judge review and its badge offered a "Judge failed" tooltip on a page correctly headed "Checks". Classification now falls back to the metric the review was queued for, and the tooltip names whichever actually failed. A review still keeps the type of the version that ran when the metric's type is changed afterwards.

### Changed
- **The gemspec advertised an MCP server with 34 tools against a real count of 53.** The description is public on the gem page, so the number was wrong everywhere the gem is listed. It now reads 53, and a spec asserts the advertised figure against `tools/list` so it cannot drift again.

## [0.28.32] - 2026-08-03

This is the first release since 0.28.24, so it also carries everything in 0.28.25 through 0.28.31, which were versioned but never published. Those sections are below in full; in short:

- **0.28.31** Prompt serving is counted and surfaced, so you can tell which prompts are live in production. (#158)
- **0.28.30** Starting a run returns as soon as the run is claimed, ending false `runs_generate` timeouts over MCP. (#150)
- **0.28.29** A run shows how often a human agreed with its judge, and says "Unverified" when nobody has checked. (#154)
- **0.28.28** A completed run whose scores cluster at the top now warns instead of presenting it as success. (#153)
- **0.28.27** The judge scores at temperature 0 by default, separately from the generation temperature. (#155)
- **0.28.26** Runs take a generation `max_tokens`, and `temperature` is settable over MCP. (#159)
- **0.28.25** Per-metric averages on `runs_get`, plus field selection, score filters and paging on `responses_list`. (#160)

**Upgrading from 0.28.24 requires `bin/rails completion_kit:install:migrations && bin/rails db:migrate`.** Three of the releases above add columns or tables: `completion_kit_prompt_serves` (0.28.31), `judge_temperature` (0.28.27) and `max_tokens` (0.28.26).

### Changed
- **The dashboard's pulse cards say something on every workspace, or they don't show up at all.** (#166) The failing-checks card sat at a permanent `0 / No failing checks this week` in any workspace with no check metrics, which is filler dressed as a signal, so it is now hidden entirely and the card row narrows to three. Where checks do exist it reads as an instrument instead of a lone weekly count: the headline is the pass rate across the trailing fortnight, a daily sparkline underneath shows the shape of it, and each bar takes the same three-tier colour as the headline so a 90% day is not painted the same red as a 25% day. A new `DashboardStats.check_activity` supplies the series.

  The failures card named the error class on every row, which truncated to an identical `CompletionKi…` and answered a question nobody was asking. Each row now names the run that failed, with the cause on hover, and the `generation` chip shortens to `gen` so the name gets the width. The trend-card headers dropped `· LAST 7 DAYS`, which repeated on three of four cards and wrapped onto a second line on each; they now read `· 7D` and `· 14D` and fit on one line. The activity card leads with the run count and demotes its sparkline to supporting texture, so a fortnight where everything landed on one day no longer reads as a broken chart.

- **The stale-metrics banner on a run now names the action it is actually recommending.** (#166) Its closing line read "Re-run to refresh the scores with the current metrics", but re-scoring the existing responses against the current metrics is precisely what **Re-grade** does, at no generation cost, so the copy was steering people toward the expensive button. It now says Re-grade, and Re-grade leads. The difference between the two actions, and the cost gap, previously appeared only in `title` tooltips and so were invisible at a glance; each button now carries its consequence on a line underneath it.

## [0.28.31] - 2026-07-30

### Added
- **Prompt serving is now visible: how often each prompt is actually fetched, and when it was last used.** (#158) CompletionKit served published prompts over the API but recorded nothing about it, so there was no way to tell which prompts are live in production, which are dormant, and which a team could safely retire. Fetches are now counted per prompt per day in a new `completion_kit_prompt_serves` table, rolled up daily so it stays bounded by prompts times days rather than growing with traffic. The prompt page shows the family total, the last-7-days count, and when it was last fetched, sitting directly under the endpoint URL it refers to. The dashboard gains a "Prompts served" card with a 14-day trend and the most-fetched prompts.

  Counting happens at the two places a consumer actually reads a prompt: the REST `show` action (covering both the slug and the numeric id) and `CompletionKit.current_prompt`, which `current_prompt_payload` and `render_current_prompt` both route through. Editing, publishing or deleting a prompt is not a fetch and is not counted. No request details are recorded, only the count: see `docs/privacy/data-flow.md`.

  The dashboard card sits outside the existing five-run gate, because a workspace that serves prompts to production and never runs an eval is exactly the audience for it. `family_key` is denormalised onto each row so a family's history survives deleting an individual version.

  **Host apps need `bin/rails completion_kit:install:migrations && bin/rails db:migrate` to pick up the new table.**

## [0.28.30] - 2026-07-30

### Fixed
- **Starting a run now returns as soon as the run is claimed, instead of holding the request open through the whole setup.** (#150) `start!` parsed the entire dataset, deleted and re-inserted a response per row, and enqueued a job per row (or per row times metric) inside the caller's request. On a normal dataset that is most of a second, which is what surfaced over MCP as a `-32603` or "operation timed out" on `runs_generate` even though the run had started perfectly well, leaving an agent unable to tell a false failure from a real one. The cheap checks still run synchronously and still fail the call immediately (bad state, empty dataset, missing output column, unconfigured provider), then the run is claimed and the expensive work handed to a new `StartRunJob`. Measured on the 150-row by 3-metric dataset in dev SQLite: the caller now blocks for a median of **47 ms instead of 787 ms, a 16.6x reduction**, with the remaining ~740 ms moved onto the worker. On a networked database the gap should be wider, since the deferred part is where the per-row round-trips live.

  The tenant columns the inserted rows need are resolved in the request, where the host's tenant context exists, and passed to the job, so a tenanted host app does not end up with unscoped responses. `StartRunJob` is a per-run singleton and re-checks the run's state, so a retry or a double submit cannot insert twice, and the completion check now ignores a run that has been claimed but whose rows have not landed yet, which would otherwise have completed it with zero responses.

### Changed
- **The run page's poll now refreshes the progress panel and the response rows, not just the status badge.** Required by the change above, since the rows no longer exist when the page first renders, but it also fixes live updating during a run: response rows previously relied on Turbo broadcasts from the worker, which do not reliably publish in production.

## [0.28.29] - 2026-07-30

### Added
- **A run now shows how often a human agreed with its judge, and says "Unverified" when nobody has checked.** (#154) The agreement maths already existed but the number only appeared in a card at the bottom of the metric page, so a run could show a confident average next to no evidence that the judge was ever right. The run status panel gains a "Judge agreement" figure beside the average score, reading the verdicts cast on that run's own responses rather than a metric's current-version sample, so the number describes the scores actually on screen. With no labels it renders an explicit "Unverified" alongside a link into the judge's agreement section rather than a blank or a misleading zero. Hidden entirely on check-only runs and when `judge_agreement_enabled` is off.

## [0.28.28] - 2026-07-30

### Added
- **A completed run whose scores cluster at the top now says so, instead of presenting it as an unqualified success.** (#153) A near-max average with almost no spread nearly always means the judge is not separating good output from bad, but nothing on the page distinguished that from genuinely excellent output, so a first-time user reads a 4.95/5 as "the model is great". A completed run now shows a warning when the mean judge score reaches 4.8 or when 90% or more of scores land on the top band, provided there are at least ten scores so the shape means something. The banner offers the two next steps that turn the warning into an action: sorting the responses worst-first to see whether the judge ever penalises anything, and jumping to the judge's agreement section to score a few outputs by hand. It lives in the polled status header, so it appears on its own when a running run completes rather than waiting for a reload.

## [0.28.27] - 2026-07-30

### Changed
- **The judge now scores at temperature 0 by default, and the judge temperature is separate from the generation temperature.** (#155) Judging previously passed no temperature at all, so every provider client fell back to its own `0.7` default. That made scoring non-deterministic: re-judging the same output could return a different score, which quietly undermines comparing one run against another. Runs gain a `judge_temperature` setting, defaulting to `0`, threaded through all three `JudgeService` callers (the review job, the prompt-improvement validator, and the metric-improvement validator, which previously each rebuilt the same config hash by hand and would otherwise have drifted apart). It is settable on the run form, the REST API, and the `runs_create` / `runs_update` MCP tools, is carried over by `rerun`, and forks a new run when changed on a run that already has responses. Above 0 the run page shows a "scores not reproducible" marker and the MCP payload returns a warning.

  Note for anyone reading the issue: its premise was slightly off. The judge was not inheriting the run's generation temperature and was not at 1.0, it was at each client's 0.7 fallback. The reproducibility problem, and the fix, are the same.

  **Host apps need `bin/rails completion_kit:install:migrations && bin/rails db:migrate` to pick up the new `judge_temperature` column.**

## [0.28.26] - 2026-07-28

### Added
- **Runs now take a generation `max_tokens`, so a prompt whose correct output is long can actually be evaluated.** (#159) Generation previously always used each provider client's built-in default (1000 for Anthropic/Azure/Ollama, 8192 for OpenAI/OpenRouter) with no way to change it, so a prompt that needs a higher cap in production got truncated output in every run and the judge scored the truncation ("the JSON is malformed, several entries missing") rather than the prompt. `max_tokens` is now a run setting on the new-run form, the REST API (`POST`/`PATCH /api/v1/runs`, returned by `GET /api/v1/runs/:id`), and the `runs_create` / `runs_update` MCP tools. Leaving it unset keeps the current per-client default. Changing it on a run that already has responses forks a new run, like the other generation settings, and `rerun` carries it over. The prompt-improvement validator regenerates with the same cap so its candidate outputs stay comparable.
- **`temperature` is now settable over MCP.** (#159) `runs_create` and `runs_update` accepted neither temperature nor any other generation parameter, so every MCP-created run silently took the column default while the web form and REST API could both set it. Both tools now accept it.

  **Host apps need `bin/rails completion_kit:install:migrations && bin/rails db:migrate` to pick up the new `max_tokens` column.**

## [0.28.25] - 2026-07-28

### Added
- **Runs now report a per-metric score breakdown, so "which metric is dragging this prompt down" no longer costs a full response dump.** (#160) `GET /api/v1/runs/:id` and the `runs_get` MCP tool return `metric_averages`: one entry per metric with its average score (`pass_rate` for checks), `count` (rows graded) and `low_count` (rows scoring below the configured medium quality threshold). The breakdown already existed for the runs index; it is now on the run payload itself and costs no extra queries.
- **`GET /api/v1/runs/:run_id/responses` and the `responses_list` MCP tool can now return just what you asked for.** (#160) New `fields` (comma-separated response keys, `id` always included, `reviews.`-prefixed keys trim each nested review), `min_score` / `max_score` (filter on a row's average judge score) and `sort` (`id`, `score_asc`, `score_desc`) parameters. Fetching the ten worst rows with only their scores is now one call instead of downloading every `input_data`, `response_text` and `ai_feedback` in the run and aggregating client-side.

### Changed
- **`responses_list` (MCP) now pages by default and returns a `{total, limit, offset, returned, responses}` envelope instead of a bare array.** (#160) It previously returned every response with no limit, which on a normal run is multiple MB and trips the MCP "result exceeds max tokens" cap. It now defaults to 50 rows (max 500) and accepts `limit` / `offset`. The REST endpoint is unchanged: it still returns a bare array with the totals in the `X-Total-Count` / `X-Limit` / `X-Offset` headers.

## [0.28.24] - 2026-07-28

### Fixed
- **An LLM-judge metric could be saved with a completely empty instruction.** (#156) A judge with no rubric has nothing to score against, but a blank instruction was allowed, producing a silently meaningless metric. Saving or publishing an `llm_judge` metric now requires an instruction ("Instruction can't be blank. An LLM judge needs a rubric to score against."); check metrics are unaffected.
- **A run where every response failed displayed as "completed" with a blank score.** (#157) `mark_completed!` set `completed` unconditionally, so a run whose generations all failed (bad model/provider/auth wiring) looked like a benign empty result instead of a broken one. When every response failed, the run is now marked `failed` with an aggregated reason ("Every response failed to generate (N of N). First error: …"), which surfaces inline through the existing failed-run status header. Partially-failed runs still complete normally.

## [0.28.23] - 2026-07-28

### Fixed
- **Editing only a prompt's name, description, or tags created a spurious new version.** A prompt with runs versioned on every save regardless of what changed, so renaming it or changing its tags (metadata that has no effect on how the prompt renders or scores) minted a new version and cluttered the version history. It now mirrors how metrics already behave: a new version is created only when a behavioral attribute changes (the template or the model); name, description, and tags update in place on the current version. The edit-form note reflects this ("changing the prompt or model saves a new version; name and tags update in place").

## [0.28.22] - 2026-07-28

### Changed
- **`start!` now bulk-enqueues its row jobs in one `perform_all_later` instead of one `perform_later` per (row × metric).** (partial #150) Starting a run held the request open while it enqueued a job per row (generation) or per row × metric (judging); on Solid Queue each was its own INSERT, so a 35-row judged run made ~140 individual enqueues, each a round-trip to the database. Over MCP that synchronous cost is what surfaced as a `runs_generate` timeout / `-32603` even though the job had started. The jobs are now enqueued in a single bulk call. Measured on 150 jobs in dev SQLite: Solid Queue INSERTs dropped from 300 to 151 and enqueue wall time from ~1119 ms to ~625 ms (~1.8x); on a networked database the win is the eliminated per-row round-trips. This shrinks the window for the timeout but the enqueue is still O(rows); the durable fix (return immediately and enqueue the run asynchronously) is tracked separately in #150.

## [0.28.21] - 2026-07-28

### Fixed
- **The runs index rendered its per-run score summaries by loading every response and review for the whole list into memory.** (#151) This is not a query-count problem (the page already eager-loaded in ~5 queries); the cost was instantiating one ActiveRecord object per review and computing `avg_score` / `metric_averages` / `check_pass_rate` in Ruby, which grows linearly with total reviews. As an org accumulates runs (the reporting org: ~20+ runs, several at 35 responses × 4 metrics), that fans out into thousands of review objects per request and, on a busy single-worker host, tips into a gateway 502. The index now computes those summaries with a constant handful of grouped `GROUP BY run_id` queries and loads zero response or review objects, injecting the results into the runs. Measured on 3,500 reviews (25 runs × 35 × 4) in dev SQLite: median render dropped from 55.8 ms to 3.6 ms (15.4x), loading 0 review objects instead of 3,500; on Postgres the gap should be wider because the row transfer is what is avoided. The batched computation is asserted to produce identical values to the per-run methods, and a request spec locks the index to a bounded query count as runs grow.

## [0.28.20] - 2026-07-28

### Fixed
- **MCP `runs_create`/`runs_update` silently dropped `metric_group_id`, producing a run that judged nothing but reported success.** (#147) Metric groups are first-class MCP objects, so `metric_group_id` reads as the natural way to attach a group's metrics — but the tools accepted only `metric_ids` and ignored anything else, so the run was created with no metrics, generation completed, and the run ended `completed` with `avg_score: null`: a green false-success. The tools now accept `metric_group_id` and expand it to the group's current `metric_ids` (explicit `metric_ids` still wins if both are passed). Independently, any MCP run payload for a run with no metrics attached now carries a `warning` ("No metrics are attached, so this run judges nothing…"), so the no-op is visible on `runs_create`/`runs_update`/`runs_get`/`runs_generate` even if metrics were dropped for another reason.

### Added
- **MCP tools `runs_regrade`, `runs_rerun`, and `runs_retry_failures`.** (#148) The engine and REST API already had these verbs, and `runs_generate` refuses on a completed run and points at them, but they weren't exposed over MCP — so re-judging an already-generated run (for example after attaching or editing metrics) forced a wasteful delete + recreate + regenerate. `runs_regrade` grades a run's existing responses with its current metrics without regenerating; `runs_rerun` starts a fresh copy; `runs_retry_failures` re-runs only failed responses (optionally limited via `only`). The shared `rerun`/`retry_failures` logic was extracted into `Run#rerun!` / `Run#retry_failures!` so the web controller, REST controller, and MCP tools now go through one implementation.

## [0.28.19] - 2026-07-28

### Fixed
- **Starting a run over a large dataset inserted every response in one `insert_all`, producing a multi-megabyte SQL string that could stall the web worker.** (#149) Since 0.28.0 a run's responses were created in a single INSERT with one value tuple per row; on a ~20k-row dataset that statement is several MB. Anything that regex-scans SQL per query (Honeybadger's breadcrumb obfuscation, Rails SQL logging) then exceeds the 1s `Regexp.timeout` and spins CPU, which on a single-worker host blocks the health check and forces a restart. The insert is now chunked into batches of `INSERT_BATCH_SIZE` (1000) rows, keeping each statement small regardless of dataset size while preserving the batched-insert speedup.

## [0.28.18] - 2026-07-28

### Fixed
- **The new Version column in the prompt-show suggestions table used a plain-text label instead of the brand's version chip.** It now renders the version with the same `ck-chip ck-chip--soft` component used for the version label on the prompt header and the prompts/metrics indexes, so it matches the rest of the app.

## [0.28.17] - 2026-07-28

### Changed
- **Rewrote the suggestion result panel to be legible to a first-time user.** The verdict was written in internal vocabulary a newcomer can't parse: "held-out responses," "re-scored," "validated"/"unvalidated," "net negative." The panel now leads with a plain verdict ("We re-ran this wording on 12 of the run's responses. It scored 4.1 now, 3.3 before" with a Better/Same/Worse tally, or "We couldn't test this rewrite" with a short explanation of what testing means and why it didn't run), shows the diff, then the reasons underneath the changes, and ends with a plain note that applying publishes the wording as a new prompt version and leaves the current one intact. The redundant "Full suggested prompt" dump is gone (the diff's suggested pane already shows the full new prompt), and the "Apply anyway" states now carry a clear warning above the button instead of only inside the confirm dialog.
- **The prompt show suggestions section is now clearer.** It's titled "Suggested improvements," renders each suggestion's reasoning as clean plain text (markdown syntax stripped) instead of raw `**bold**` and backticks, and adds a narrow Version column showing the prompt version each suggestion targets. The list eager-loads its runs and prompts to avoid per-row queries.

### Fixed
- **Adding the Version column exposed an off-by-one in the suggestions-table column widths.** The table sized columns by position, so the new column shifted every rule by one and the Reasoning cell inherited a narrow `nowrap` width meant for the Applied column, spilling its text across the row. The widths are corrected for the six-column layout and the Run name now ellipsizes instead of overflowing.

## [0.28.16] - 2026-07-28

### Changed
- **The suggestion rationale now renders its markdown instead of showing raw `**` and backticks.** The "Why these changes" text is model-generated markdown but was printed literally with `simple_format`, so bold labels showed as `**like this**`. It now renders inline bold and code (safely, still HTML-escaped) while keeping paragraphs and bullets. The heading was relabeled from "Why these changes" to "Reasons for suggested changes."

### Fixed
- **The suggestion "Apply anyway" button gave no on-screen reason for the "anyway."** (#146) When a rewrite couldn't be re-scored, or scored lower than the original, the only explanation was inside the post-click confirm dialog, so the button read as a contextless dead-end (and the unvalidated case showed no scoreboard at all). A short caveat now appears inline above the button before the click: "Couldn't be re-scored against this run's responses, so applying it is unvalidated," or, for a lower-scoring rewrite, "Scored 3.2 on the held-out responses, below your original's 3.8" (with the actual numbers). The confirm dialog stays as a backstop.

## [0.28.15] - 2026-07-28

### Fixed
- **The prompt show page fired ~47 queries (about 9.5s) even on trivial data.** (#145) The page has no single slow query; it was the count of round-trips, all N+1s that scale with runs × versions. Four fixes: `Run#reviews_for_summary` (which backs `avg_score`/`metric_averages`/`check_pass_rate`) now reuses eager-loaded reviews when the run's responses are already loaded with their reviews, instead of always re-querying — so those per-run scores are free on this page, which eager-loads everything, while the run page keeps its single query. The versions table now groups the controller's already-loaded `@runs` in Ruby instead of re-running `v.runs.display_scoped` per version, which had discarded the eager-load and re-queried each run's reviews. The "Suggest improvements" check uses the loaded `:reviews` rather than a fresh `responses.joins(:reviews).exists?` per run. And the runs table's per-row tag rendering no longer fired a tags lookup per run — run `:tags` are eager-loaded. A query-count regression test asserts the page stays bounded as runs are added.

## [0.28.14] - 2026-07-28

### Fixed
- **A long model ID in the prompts list overlapped the Best Score badge.** (#144) The Model column was a fixed 12rem with `white-space: nowrap` but no overflow clipping, so a full dated Anthropic ID (for example `claude-haiku-4-5-20251001`, ~24 characters) spilled out of its cell and rendered on top of the next column's score badge. The column is now 15.5rem (enough for a dated snapshot ID to show in full), clips its overflow so nothing can bleed into the score column, and ellipsizes the model chip as a backstop for anything even longer.

## [0.28.13] - 2026-07-27

### Fixed
- **The JetBrains Mono web fonts 404'd under Propshaft (three failed requests per authenticated page load).** (#143) The `@font-face` rules used `url('completion_kit/jetbrains-mono-400.woff2')`. Propshaft resolves `url()` relative to the stylesheet's own directory (`completion_kit/`), so it doubled the path to `completion_kit/completion_kit/…` and left it un-rewritten, producing the 404. Dropped the redundant `completion_kit/` prefix so the path resolves to the font's logical path and Propshaft rewrites it to the digested URL.

### Changed
- **Dropped the unused `sassc-rails`, `bootstrap`, and `jquery-rails` runtime dependencies and made the engine Propshaft-native.** The engine ships plain CSS and vanilla JS: there is no SCSS, no Bootstrap markup, and no jQuery anywhere in it, so all three were dead weight. `sassc-rails` in particular dragged `sprockets` / `sprockets-rails` into every host app's bundle, which both bloated installs and made the font `url()` above resolve inconsistently between pipelines. The engine's asset-precompile registration now tolerates a Propshaft `config.assets` (which has no `precompile` list), and the bundled standalone app was migrated from `sprockets-rails` to Propshaft (the Rails 8 default). Host apps that genuinely used Bootstrap, jQuery, or Sprockets *through* this gem should declare those gems themselves; the font fix targets Propshaft, so a host app still serving assets through Sprockets will see the monospace font fall back to the system default until it moves to Propshaft.

## [0.28.12] - 2026-07-27

### Security
- **Hardened the file-upload paths against denial-of-service.** (#142) Two upload handlers read the whole uploaded file into memory with no size limit (the promptfoo import and the API dataset upload), and the promptfoo YAML parse allowed alias expansion (a "YAML alias bomb" where a small file expands exponentially in memory). None allowed code execution (`YAML.safe_load` still blocks object instantiation), but all were memory-exhaustion vectors. Fixes: a configurable `config.max_upload_bytes` (default 25 MB) is now checked against the upload's size **before** it is read, returning `413 Payload Too Large` on both the web import and the API dataset endpoints; `Dataset` validates that `csv_data` is within that limit so the model layer is bounded on every path (API, web, and direct writes); the promptfoo importer caps its input size and no longer parses YAML with `aliases: true`, closing the alias-bomb vector. Host apps can raise or lower the limit via `config.max_upload_bytes`.

## [0.28.11] - 2026-07-21

### Fixed
- **The run status panel fired an N+1 across the entire run (not the paginated page), dominating the page load.** (#135) `Run#avg_score`, `#metric_averages`, and `#check_pass_rate` each did `responses.flat_map(&:reviews)`, loading every response and then each response's reviews one query at a time, so a 2000-response run ran ~2000 queries (~19s). The three methods now share a single memoized `reviews_for_summary` load (`Review.where(response_id: responses.select(:id))`), so the panel issues one query regardless of run size. Locked in by a query-count regression test. Independent of the #132 and #133 fixes, which is why the page stayed slow after both.
- **The run page parsed the entire dataset CSV on every load to render a 50-row preview.** (#136) On a 20k-row / 834 KB dataset this cost hundreds of milliseconds of view time and GC churn per load. Three fixes: removed dead code that split the whole CSV into lines for nothing; the dataset-preview modal now reads row by row and stops after 51 (correctly handling quoted newlines) instead of `CSV.parse`-ing the whole file; and `Dataset#row_count` (called twice per page) now streams the count without materializing every row and memoizes the result. On a 10k-row CSV the modal read dropped from ~38 ms to ~0.3 ms.

## [0.28.10] - 2026-07-21

### Fixed
- **The run page fired a per-row query for the Status column (N+1), independent of response size.** (#133) The page eager-loads `:reviews`, but `Response#fully_reviewed?` called `reviews.where(status: …).pluck(:metric_id)`, which builds a fresh relation and hits the database on every call, discarding the eager-loaded association. `_response_row` calls it for every succeeded row, so a 100-row page ran ~100 extra queries; this was the dominant cost on large runs with short bodies (which the 0.28.9 preview change did not help). It now filters the already-loaded `reviews` collection in memory, matching the other reviewed-state helpers on the model. Combined with the memoized `run.metric_ids`, the responses table now issues a bounded number of queries regardless of row count, verified by a query-count regression test.

## [0.28.9] - 2026-07-21

### Fixed
- **The run page fetched the full response body for every row when the table only shows a 600-character preview (~25x over-fetch).** (#132) On a run with long outputs (production averages ~16 KB per response, up to ~19 KB), one 100-row page pulled ~1.5 MB of `response_text` out of Postgres just to truncate each to 600 characters in Ruby, discarding ~96% of it. The responses index now loads a database-side preview via a new `Response.with_body_preview(n)` scope (`SUBSTR(response_text, 1, 700)`, portable across Postgres and SQLite) instead of the full column, cutting the page's response payload about 25x for long-output runs. The full body is still loaded where it is actually needed (the response detail page and the per-row Turbo broadcasts), so nothing else changes. Works on both the default and the score-sorted (gradable) orderings.

### Changed
- **Restyled the responses pagination control.** The Prev / "Page X of Y · N responses" / Next bar was left-aligned and read as unstyled; it is now centered with a separating top border.

## [0.28.8] - 2026-07-21

### Accessibility
- **WCAG 2.1 AA pass over the authenticated product surfaces (prompts, datasets, metrics, metric groups, runs, tags, providers), part 1 of 2.** (#126) An axe-core sweep across 23 surfaces plus a manual code audit produced a set of shared-component fixes, now applied:
  - **Contrast.** Tag colour pills (`.tag-mark`) put same-hue text on a same-hue fill (2.3–4.4:1); the label is recoloured to a light tint of the hue so every tag clears 4.5:1. This cleared the entire contrast cluster (was ~115 axe nodes across the tag-showing pages). Chip and pending-badge borders were raised to `--ck-line-strong` for 3:1 non-text contrast.
  - **Use of colour.** Metric pips and the run-status dot conveyed pass/fail/score by colour only, with the text label removed from the accessibility tree; each pip is now `role="img"` with an `aria-label` ("Tone score 5.0", "Coverage 80% pass rate"), and the run-status dot carries a visually-hidden status word.
  - **Keyboard.** Focus-visible rings were added to the temperature slider, select options, disclosure toggles, the tag-picker input, and the settings menu (they set `outline: none` with no replacement). The responses table's hover-to-expand now also expands on keyboard focus (`:focus-within`). Version-history and suggestion rows that navigated by click only now carry a real keyboard-reachable link.
  - **Names and structure.** Every page now sets a distinct `<title>` (was all "CompletionKit"). Icon-only controls (copy, the `Δ` and `→`/`↗` glyphs, diff triggers) got accessible names with the decorative glyphs hidden from screen readers. The dataset-preview, metric-version-diff, and prompt-version-diff dialogs got `aria-labelledby`. Metric rubric-editor textareas got labels; form validation errors are now tied to their fields via the shared `aria-invalid`/`aria-describedby` helpers; the metrics checkbox groups became labelled `role="group"`s. In-flow `.ck-link` links are underlined so they are not distinguished by colour alone.
- Verified with axe-core (0 violations across all 23 surfaces), a keyboard walkthrough (focus rings, focus-driven expand, tab reachability), and the full suite. The remaining part 2 (screen-reader announcement of live run/discovery progress) is held pending a screen-reader verification session.

### Changed
- Migrated the SimpleCov config off the APIs deprecated in SimpleCov 1.0 (`add_filter`/`add_group` → `skip`/`group`); coverage enforcement is unchanged.

## [0.28.7] - 2026-07-21

### Changed
- **The MCP endpoint now serves discovery (`initialize`, `tools/list`) without a token; everything that touches org data still requires one.** (#131) Previously the whole endpoint was gated, so registries and health-checkers could not introspect the toolbox without credentials and a hosted server showed as "requires authentication" instead of surfacing its tools. Auth is now method-aware: `initialize`, `tools/list`, and `notifications/initialized` return only static, org-agnostic data (protocol capabilities and tool names + input schemas, which are already public API surface) and are answered without a token; `tools/call` and any other data method still require the Bearer token, which identifies the org. The open methods stay bounded by the same per-IP API rate limit as the rest of the API (120 requests/minute by default), and MCP session rows self-prune on every new session and expire after an hour.

### Fixed
- **`McpController` could stop a host app from booting.** (#130) The GET/405 fix in 0.28.6 added `skip_before_action :authenticate_api!, only: :stream` without `raise: false`, which raised at class-load time in any host app that had removed or replaced the engine's `authenticate_api!` callback (for example an app with its own tenant-aware auth). The skip now passes `raise: false`, so it is a no-op when the callback is not in the chain, matching how the engine's other controllers tolerate host-app customization.

## [0.28.6] - 2026-07-21

### Fixed
- **The MCP endpoint returned 404 on a `GET`, which failed directory health checks.** (#129) The endpoint only routed `POST` (the JSON-RPC handshake and tool calls) and `DELETE` (session teardown), so a `GET` matched no route and Rails returned 404, which reads to tooling (and registries like Glama) as "endpoint does not exist" even though the server is fully functional over `POST`. A `GET` (and `HEAD`) now returns `405 Method Not Allowed` with an `Allow: POST, DELETE` header, which is the correct streamable-HTTP response for a server that does not offer a server-initiated SSE stream. The probe is answered without a token, so an unauthenticated health check sees `405`, not `401` or `404`.

### Changed
- **Routine dependency updates (non-security).** Bumped `puma` (7.2.1 → 8.0.2), `solid_cable` (3.0.12 → 4.0.0), `sqlite3` (2.9.2 → 2.9.5), and `bootsnap` (1.23.0 → 1.24.6) in the standalone app, and raised the `simplecov` development dependency to `~> 1.0` (1.0.1). Verified: full suite green at 100% line and branch coverage under simplecov 1.0, the standalone boots and serves under puma 8, and Solid Cable 4 broadcasts write correctly against the existing `solid_cable_messages` schema (its schema already matches v4, so no migration is needed).

## [0.28.5] - 2026-07-17

### Security
- **Provider API keys no longer leak into error tracking or the database on a bad-credential model discovery.** (#118) When a provider returned 401/403 during model discovery, the response body (which for OpenAI echoes the submitted key) was raised as the error message and then sent to the host app's error reporter (Honeybadger/Sentry/etc.) and stored in the `discovery_error` column. Two changes: the discovery service now redacts the submitted key, `sk-…` keys, `Bearer …` tokens, and `API key provided: …` echoes from every provider error message (discovery and per-model probe errors), and the discovery job now treats an expected `DiscoveryError` (a bad key is user input, not an app fault) as handled and does not report it to `Rails.error`, while genuinely unexpected errors are still reported.

### Fixed
- **A crafted array `page` parameter no longer 500s the run page.** (#114) `RunsController#show` did `params[:page].to_i`, which raised `NoMethodError` on a non-scalar param such as `?page[]=1`. It now coerces with `params[:page].to_s.to_i`, so any non-scalar falls back to page 1.

### Changed
- **Dependency and Dependabot housekeeping.** Bumped vulnerable transitive gems flagged by Dependabot: `faraday` (recursion DoS), `concurrent-ruby`, `nokogiri`, `net-imap`, and `websocket-driver`, in both the engine and standalone lockfiles. Added the `standalone/` directory to `.github/dependabot.yml`, which previously only watched the engine root, so the deployed app's dependencies are now covered too.

## [0.28.4] - 2026-07-15

### Changed
- **Run comparison table is now built around the decision.** The separate "A score" and "B score" columns are collapsed into one "A → B" column that shows both scores as badges side by side, so you see the shift (for example 5.0 → 3.0, green to amber) at a glance. Both badges are links: click either one to open that side's full response and read the judge's reasoning, so you can dig into the details before deciding. The delta is promoted to a single indicator with direction and colour: a green ▲ when B improved, a red ▼ when it regressed, and a muted "=" when nothing changed. The two version columns are folded into one that shows the version once when A and B match and "v1 → v2" only when they differ, so identical versions stop taking up space. The metric name is brightened and sits right next to its scores instead of drifting to the far left of the row, so it no longer gets lost as your eye travels across. When B has no matching response the cell reads "5.0 → —".

## [0.28.3] - 2026-07-15

### Changed
- **Run comparison table is readable.** It was rendered with every column the same width, so the metric names wrapped onto two or three lines while the score columns sat mostly empty. Columns are now sized to their content: the metric name gets the room and stays on one line, and the score, delta, and version columns are tight. The cryptic "1 / B" case label is replaced by a clear "Case N" heading with separate "A" and "B" links (tooltipped with each run's name) to open that case in either run, and the header now spells out that the delta is B minus A. Each case is grouped into its own block with one divider between cases and a single hover highlight over the whole case, replacing the old per-row highlight that lit only part of a case because of the spanning cell. In a very narrow window the table scrolls sideways within its own box instead of pushing the page.
- **Responses table shows more of the response.** The Metrics column was far wider than its small pips needed, squeezing the Response text. Metrics is trimmed to fit its content (pips wrap if a run has many metrics) and the Status column is a touch narrower, so the Response column is meaningfully wider.

## [0.28.2] - 2026-07-15

### Fixed
- **The responses-table hover-expand from 0.28.1 never actually expanded.** The Response cell is a greedy column (`max-width: 0; width: 100%`), which only stays width-bounded when the cell also clips its overflow. 0.28.1 dropped `overflow: hidden` from that cell, so the preview span had no width to clamp against and the hover class had nothing to grow. Restoring the clip makes the cell expand from one line to twelve on hover, as intended. Verified in-browser: the row grows from ~57px to ~309px and the line-clamp goes 1 → 12 when hovered.

## [0.28.1] - 2026-07-15

### Changed
- **Response text is readable again.** In the run's responses table, the Response cell now expands on hover (like the CSV preview cells, after a short delay) instead of staying truncated on one line, so you can read a response without opening it. On the response detail page, the Input, Response, and Expected code blocks wrap long lines (with vertical scroll for very tall payloads) instead of clipping them off the right edge.

### Fixed
- **Large runs (thousands of rows) timed out on start and rendered every response on one page.** (#113)
  - `Run#start!` now bulk-inserts response rows in a single `insert_all` instead of a per-row `create!` loop. The dominant cost was the per-row `after_save_commit` Turbo broadcast firing once for every row on start (thousands of partial renders + ActionCable pushes); bulk insert skips those, so starting a 2000-row run drops from tens of seconds to about a second and no longer times out. Row jobs are still enqueued after the rows are written; the run page's status polling shows progress as they process.
  - The run detail page paginates its responses table (100 per page, with Prev/Next) instead of loading and rendering every response into one giant DOM.

### Changed
- **Trimmed noisy copy and made the delete UX consistent.** The Azure API-version field hint is now just "Optional. Leave blank to use Azure's v1 API." The provider delete control is a plain, always-enabled trash button like every other resource's — the previous disabled button plus a permanent "still in use … remove those references" notice is gone. Attempting to delete an in-use provider now surfaces a short flash on click ("&lt;provider&gt; is in use by N judge runs and can't be deleted.") instead of a persistent banner. The unused `disabled`/`title` options were dropped from the shared delete-trigger helper.

### Fixed
- **The Tags API docs were inconsistent about `tag[]` filtering.** The Tags section said every index page could be filtered by tags, but only the Runs and Prompts endpoints documented it — even though the Metrics, Datasets, and Metric Groups list endpoints all support `?tag[]=name` too. All five taggable list endpoints now document `tag[]` filtering and pagination consistently, and the intro names the five resources and spells out the OR semantics.

### Fixed
- **The "stale metric versions" banner fired confusingly ("scored by v1; live is v1") for a metric published only once.** The staleness check compared metric versions by row **id** but displayed the version **number**, so two same-number rows (from the #111 race, on deployments that haven't run that dedupe migration yet) were flagged as stale against each other. Staleness is now determined by version **number** — a review is only stale when the metric actually moved to a different version — so the banner, the per-review "scored on vX → vY" chip, and the `retry_failures` 409 guard no longer false-positive on duplicate rows. Running the 0.27.5 migration still removes the duplicate rows themselves.

### Fixed
- **Documentation audit across every doc surface.** A full cross-check of the API reference, MCP tool descriptions, and READMEs against the code corrected 21 inaccuracies. Highlights: **metric groups are now documented as taggable** (they were the only taggable resource omitted from the tagging docs); the run `/rerun` status is 202 (not 201); the `/compare` one-sided-case behavior, the responses `status` enum (added `retrying`), and the prompt PATCH versioning behavior were corrected; the provider-credentials `api_key` requiredness, one-per-provider rule, and in-use DELETE (422) are documented; the promptfoo import response shape and the agreements contract (conditional `corrected_score`, idempotent create 201/200, `judge_agreement_enabled` gating, the nested index endpoint) were corrected; the `judges_compare` and `judges_replay` MCP tool descriptions were fixed; and the READMEs gained the Azure AI Foundry provider and the provider/encryption env vars.

### Fixed
- **API reference documentation accuracy.** Corrected several stale or misleading entries in the API reference: `/agreements` POST marked `created_by` required when it is optional (defaults to `"api"`); provider-credentials POST omitted `azure_foundry` from the provider list and the `api_version` param, and flatly labeled `api_endpoint` optional when it is required for `azure_foundry`; the run `/compare` response shape was missing `left_run_id`/`right_run_id`; `/runs` POST omitted `temperature`; and `retry_failures` didn't mention its optional `only` param or 409 response. Added missing curl examples across create, update, publish, and action endpoints (provider credentials incl. an Azure variant, metric groups, PATCHes, and a filtered `GET /runs`). (#112)

### Fixed
- **A race in `MetricVersion.ensure_current_for` created duplicate `v1` metric versions.** When a run first scored a metric with no published version, parallel review jobs each created a `current: true, version_number: 1` row — the `(metric_id, version_number)` index wasn't unique and the app-level uniqueness check has a check-then-insert race. The run page then warned "scored against metric versions that are no longer live (scored by v1; live is v1)" for a singly-published metric. Version creation is now race-safe (it recovers by re-finding the current version on a unique violation), a migration promotes `(metric_id, version_number)` to a **unique** index, and any pre-existing duplicates are collapsed (reviews and agreements re-pointed to the surviving row, extras removed) before the index is applied. (#111)

## [0.27.4] - 2026-07-14

### Fixed
- **Provider HTTP errors (e.g. OpenRouter 402 "insufficient credits") failed hard and paged the error tracker on every row instead of recording a clean failed response.** During generation and judging, a provider HTTP error is now recorded as a `failed` response/review carrying the provider, status, and message — not raised as a generic error and reported as noise. (#110)
- **Transient errors weren't actually retried.** A handler-ordering bug (`rescue_from(StandardError)` shadowing `retry_on`/`discard_on`) made rate limits and timeouts fail on the first attempt; they now retry with backoff and record a terminal failure only after exhaustion. This also surfaced a latent bug where the rate-limit backoff was never computable.
- **A failed judge review displayed as "Pending"** with no error; it now shows the failure.

### Fixed
- **Deleting a metric that had been used in a run raised a foreign-key violation (500).** `Metric` had no cleanup for its `completion_kit_run_metrics` join rows, and that FK does not cascade, so deleting any metric ever attached to a run failed. `Metric` now destroys its `run_metrics` on delete; reviews keep their score snapshot (their metric link is nullified). An audit of every other delete action found no further instances. (#109)

### Fixed
- **A malformed tag name returned a 500 instead of a validation error.** Assigning a tag with punctuation (e.g. `c++`) or over 64 characters raised mid-assignment on every tagged form and API (prompts, metrics, runs, datasets, metric groups). Tag names are now validated as part of the record and rejected with a clear message and a 422, and no partial tag rows are created on a failed save. The submitted tag selection — including a just-typed new tag — is preserved when a form fails validation for any reason.

### Fixed
- **Re-versioning a prompt whose model was later demoted by discovery 500'd.** The 0.27.0 generation-model validation fired on the re-version path, so editing any field of a prompt that has runs — or applying a suggestion — raised an unhandled 500 once discovery demoted its in-use model. A model inherited from the version being edited is no longer re-validated, so those edits succeed; genuinely selecting an unusable model now returns a clean 422 (web and REST) with no partially-written version. Importing a promptfoo config whose resolved model can't generate reports an error instead of 500ing. (#108)
- **A failed response with no error detail rendered an empty error box.** The response detail page now falls back to the error message, or "The provider returned no error detail." when nothing is set, instead of a blank block. (#107)

## [0.27.0] - 2026-07-13

### Added
- **Azure AI Foundry providers now show how many models are available to deploy.** A Foundry project endpoint only serves the models you've actually deployed, but the resource holds a much larger catalog you can deploy from. The models card now shows a **"N models available to deploy in Azure AI Foundry →"** line, so the full catalog is visible and one click from the portal without cluttering the usable-model list. Only your real deployments stay selectable for prompt runs and judges.
- **Prompts can no longer be saved with a model that is known not to generate.** The prompt dropdown already hid non-generation models, but the REST API, MCP tools, and imports accepted any model string. A prompt whose model has been discovered and confirmed unusable for generation is now rejected; unknown and not-yet-probed models are still allowed.

### Changed
- **The empty-models state reuses the "Available models 0" summary** with the circular refresh icon, replacing the standalone "Discover models" button.

## [0.26.8] - 2026-07-13

### Fixed
- **Failed responses couldn't be opened.** Only succeeded responses were clickable in a run's responses table, so a failed response (e.g. a provider error) could only be read from its truncated cell. Failed responses are now clickable through to their detail page, which shows the **full error** — provider, status, and complete message — in a distinct error block instead of an empty response.

## [0.26.7] - 2026-07-13

### Fixed
- **A provider with no models had no way to trigger discovery.** The "Refresh models" control only appeared once models already existed, so a provider that discovered nothing (or hadn't run discovery yet) was stuck with an empty card and no button. The models card now always shows a **"Discover models"** button when there are no models.
- **Removed a duplicate "Model" row on the run page.** 0.26.6 added a Model row to the run configuration, but the generation model is already shown as a chip beside the prompt version, so it appeared twice. The row is gone.

## [0.26.6] - 2026-07-13

### Fixed
- **Azure AI Foundry project endpoints discovered a wall of catalog models (or nothing) instead of the project's own deployments.** A Foundry *project* endpoint (`…services.ai.azure.com/api/projects/<project>`) doesn't serve the classic `/openai/deployments` API, and `/openai/v1/models` returns the entire model catalog (hundreds of models, with duplicate ids). Discovery now detects a project endpoint and lists the project's actual deployments at `GET {endpoint}/deployments?api-version=v1`, using each deployment name as the model id.
- **Newer Azure models (gpt-5.x, o-series) failed generation and capability probing** because they reject `max_tokens` in favor of `max_completion_tokens`. The Azure client and the discovery probe now retry with `max_completion_tokens` when a model rejects `max_tokens`, mirroring the existing temperature fallback.
- **The provider new/edit breadcrumb read "Settings" instead of "Providers"** (the link already pointed at the providers list).

### Added
- **The run detail page now shows the generation Model** in the run configuration, alongside Judge, Temperature, and the rest.

## [0.26.5] - 2026-07-13

### Fixed
- **Model discovery crashed with "Validation failed: Model has already been taken" when a provider's model list contained a duplicate id.** Reconciliation snapshotted the existing models once and then created a row per listed id, so a repeated id tried to insert the same `(provider, model_id)` twice and tripped the uniqueness validation. Duplicate ids are now collapsed before reconciling. (Azure's v1 `/openai/v1/models` catalog can list the same id more than once, which is where this surfaced.)

## [0.26.4] - 2026-07-13

### Added
- **Azure AI Foundry now works without an api-version, via Azure's v1 API.** Leaving the API version blank routes generation, judging, and discovery through the v1 endpoints — `POST /openai/v1/chat/completions` (deployment name in the body) and `GET /openai/v1/models` — with no `api-version` query parameter. Setting a dated version still uses the legacy data-plane API (`/openai/deployments/…?api-version=…`), which lists your specific deployments during discovery. The api-version field is now optional (and only shown when Azure AI Foundry is the selected provider).

## [0.26.3] - 2026-07-13

### Fixed
- **The metric edit form silently lost saves — and "Discard draft" could destroy the whole metric — whenever a draft or suggestion banner was showing.** The banner's `button_to` actions were nested inside the edit `form_with`; an HTML5 parser collapses the nested forms, orphaning the Save button and metric fields and folding the discard action's `_method=delete` into the edit form (so saving did nothing and discarding a draft issued `DELETE /metrics/:id`). The banners now render as their own top-level forms outside the edit form.

### Changed
- **The delete control on every edit form is a trash icon beside Cancel/Save again**, instead of a labeled button below the card. It stays its own top-level form via the HTML5 `form=` attribute, so it still issues a real `DELETE` rather than the swallowed `PATCH` the nested version produced.
- **Confirmations now use a branded in-app modal** instead of the browser's native dialog, across every `data-turbo-confirm`. Destructive actions get a red confirm button and focus Cancel; other confirmations get a neutral button. The dialog is an `alertdialog` and describes its message to assistive tech.
- **The API version field only appears for the Azure AI Foundry provider**, toggling as the provider changes, since no other provider uses it.

## [0.26.2] - 2026-07-13

### Fixed
- **Delete on the tag, prompt, dataset, metric, and metric-group edit forms silently saved instead of deleting.** The same defect fixed for provider credentials in 0.26.1 was still live on every other resource: the delete `button_to` sat inside the edit `form_with`, and HTML5 parsing collapses the nested forms into one, so clicking the trash icon submitted the edit form as a `PATCH` rather than issuing a `DELETE`. Each delete control is now its own top-level form, rendered through a shared `delete_action` partial, and a request spec per resource parses the page with the browser-accurate HTML5 parser to assert the delete form is separate from the edit form.

### Changed
- **The delete control on every edit form is now a labeled destructive button instead of a bare, easily-missed trash icon.** An in-use provider credential now shows that button disabled alongside the reason it can't be deleted, rather than hiding the control entirely and leaving it looking absent.

## [0.26.1] - 2026-07-09

### Fixed
- **The provider-credential delete control did nothing (it silently saved instead).** The delete `button_to` was rendered inside the edit `form_with`; a `button_to` emits its own `<form>`, and HTML5 parsing collapses the nested forms into one, so Turbo read the first `_method` (`patch`) and clicking the trash icon submitted the edit form as an update rather than issuing a `DELETE`. The delete control is now its own form outside the edit form, so it actually deletes. A request spec now parses the rendered page with the browser-accurate HTML5 parser and asserts the delete form is separate from the edit form. Deletion via the REST API and MCP was already correct.
- **A credential deleted while its discovery job was in flight crashed the job's error handler.** `ModelDiscoveryJob`'s `rescue_from` reloaded the credential with `ProviderCredential.find`, which raised `RecordNotFound` if the credential had since been removed (now possible), turning a benign situation into an unhandled error. It uses `find_by` and returns early when the credential is gone.

## [0.26.0] - 2026-07-08

### Added
- **Native Azure AI Foundry provider (#104).** A first-class `azure_foundry` provider type backed by the Azure OpenAI data plane, so a Foundry/Azure OpenAI endpoint no longer has to masquerade as a custom Ollama endpoint (which 404s on discovery). Adds an `api_version` field, discovery via `GET /openai/deployments`, and an `AzureFoundryClient` that generates and judges against a deployment (`POST /openai/deployments/{name}/chat/completions`) with `api-key` auth. Discovered deployments are probed like the other providers, the existing SSRF/internal-address guard still applies to the endpoint, and the provider is wired through the form, REST API, and MCP.
- **Delete an unused provider credential (#106).** Provider credentials were the one resource with no destroy path. You can now remove a credential that nothing references from its edit page; the guard reuses the existing `prompt_count`/`judge_count` usage signals, refuses deletion when a prompt or run still uses one of its models (explaining what), and cleans up the provider's discovered `Model` rows on delete. The guard lives on the model, so the REST API and MCP `delete` inherit it instead of silently orphaning models or removing an in-use provider.

### Fixed
- **OpenRouter models never showed judge capability, leaving a wall of "?".** OpenRouter is discovered from published metadata rather than live probing, but judging was left `nil` ("unknown") and only promoted by a successful run, so any model discovered after probing was disabled showed "?" forever, and whether a tenant saw ✓ or "?" depended only on when its catalog was discovered. Judge capability is now derived from the same text-output signal as generation, on both new and existing models, so a refresh resolves every OpenRouter model to a consistent judge state at no cost.
- **Model-discovery failures for custom endpoints leaked the internal `ollama` slug and gave opaque 404s (#105).** A user pointing the generic OpenAI-compatible option at, say, an Azure endpoint saw "ollama model list request failed (404)". Discovery failures on that path now use provider-neutral copy, say what to check on a 404, point Azure hosts at the dedicated Foundry provider, and are reported as handled configuration errors rather than unhandled application bugs.

## [0.25.3] - 2026-07-06

### Fixed
- **A long run name overlapped the next column in the runs table.** The name's ellipsis truncation was set on the inner `<strong>`, but its link wrapper was a flex item with the default `min-width: auto`, so it refused to shrink and overflowed the fixed-width first column into "Responses". The link now carries the truncation and `min-width: 0`, so long names clip with an ellipsis. Fixes every runs table (dashboard, runs index, dataset and prompt show pages), which all share the one component.

### Fixed
- **Cross-links on a record's show page produced a malformed URL like `datasets/4.4`.** `ck_engine_path_options` threaded the current page's engine `:id` (and `:format`) from the route recall into every `ck_*_path` helper, so a link to a sibling record on a member page (for example the dataset link in a run row on the dataset show page) had the stale id spill into the `:format` segment. It now keeps only the host mount's own scope segments (such as an org slug). The dataset "Download CSV" link threads the same scope options for consistency.

### Fixed
- Added breathing room below the tag chips on the dataset and run show pages; the standalone header tag row butted against the following section heading (for example "CSV preview"). The metric page, where the tags sit inside the page header, is unchanged.

## [0.25.0] - 2026-07-06

### Added
- **`config.on_run_started` lifecycle callback (#102).** The sibling to `on_run_created`: an observe-only seam fired once each time a run transitions into `running`, so a host can meter the billable event (LLM spend begins at start, not creation). A single `after_update_commit` guard covers every path that (re)starts work — the initial `start!`, `retry_failures`, and `regrade!` all flip status to `running` — so no start is missed. A rerun fires `on_run_created` and `on_run_started` once each. A raising host callback is reported through `Rails.error` and never aborts the run; the veto/gate seam remains deferred.

## [0.24.0] - 2026-07-06

### Added
- **Pick which dataset column is the answer key, per run (#98).** The per-row ground-truth column was a hidden convention: only a column named exactly `expected_output` was recognized, so an answer key named anything else meant every `compare_to: expected` check silently failed with "no expected value for this row". A new optional `expected_column` on runs (mirroring `output_column`) lets you point at any column; it is exposed through the run form, the REST API, and MCP, copied on rerun, and soft-validated only when explicitly set. The dataset form now surfaces the recognized `expected_output` and `actual_output` columns with a live header preview, and the run form warns when a selected check grades against the answer key but the dataset lacks the column. No new table; `expected_column` rides the existing run row.
- **`config.on_run_created` lifecycle callback (#101).** A first-class seam for host apps to observe run creation from every entry point (web, API, MCP, rerun, fork), fired once per successful create via an `after_create_commit`, replacing the need to monkey-patch controllers and the MCP dispatcher. A raising host callback is reported through `Rails.error` and never turns run creation into a 500. Metrics and tags are attached after the callback fires; a veto/gate seam is deferred.

### Fixed
- **A blank cell in the graded column no longer crashes a score-only run.** `start!` raised a `RecordInvalid` mid-transaction (the response presence validation rejected the empty string), leaving the run stuck in `pending` with no responses, no failure summary, and a 500 at the API layer. A blank cell is now a legitimate graded value: the row is created and the check fails it against the row's expected value with a clear detail. Any other row that cannot be built now fails the run with a row-scoped `failure_summary` instead of raising.
- **A provider's judge count and last-used time are lifetime again, not retention-scoped (#96).** `judge_count` and `last_used_at` on a provider credential applied the host's `runs_display_scope` (retention window), so a provider whose runs had all aged out showed "0 judges" and "Never used" next to a real lifetime `prompt_count`. Retention scopes run lists, not provider history; both stats now count across all runs.
- **Editing a run with results no longer 500s on an invalid generation field.** When a change forks a new run, the fork went through an unrescued `Run.create!`, so an invalid value (for example an answer-key column the dataset lacks) raised instead of re-rendering the edit form. The fork path now validates and re-renders with the field error, matching the create and in-place-update paths.

### Changed
- Reworded the `runs_generate` MCP tool description to say it starts every run, including score-only runs; the old wording ("using its prompt and dataset") suggested it did not apply to prompt-less runs, so they were left sitting in `pending`.

## [0.23.0] - 2026-07-04

### Removed
- **Dropped the `no_refusal` check kind and its starter.** It was a preset, not a capability: a fixed, hidden English phrase list dressed up as a first-class rule, and the "Is not a refusal" label promised detection it could not deliver (it missed off-script refusals and flagged legitimate uses of the same phrases). Anything it did can be built explicitly with a `not_contains` or `regex` check, and real refusal detection belongs to an LLM judge. Existing `no_refusal` metrics stop validating; recreate them as a `regex` check or a judge metric if you need them.

### Changed
- Reworded the "Field in the answer key" help text on the check builder to drop a domain-specific example value and the sentence that repeated the option above it.

## [0.22.0] - 2026-07-04

### Added
- **Deterministic checks can now grade against each row's own answer key (#97).** The `contains`, `not_contains`, and `equals` checks gained a `compare_to` source: compare every output against one fixed value you type (the default, unchanged), or against each row's own `expected_output` (the ground-truth column). This makes exact, per-row grading of extraction and classification datasets possible with no LLM judge and no external runner. Pick which part of the output to read (whole response or a `json_path`), and set `expected_path` to dig into the expected value when the answer key is itself JSON. A row with no expected value fails cleanly with a clear reason. Surfaced through the check builder, the REST API, and MCP, plus a new "Matches the answer key" starter metric. No schema change; the config rides the existing `check_config` JSON.

### Changed
- **The metric form has a consistent vertical rhythm.** Stacked fields in the check and judge builders were cramped at a tight gap meant for label-to-input spacing; they now use a single `--ck-field-gap` token so the space between fields matches the rest of the form.

### Fixed
- **Hidden check-builder checkboxes no longer render.** A `label.ck-checkbox` had no `[hidden]` rule, so a checkbox the form meant to hide for the chosen rule (for example Multiline on an equality check) stayed visible.

## [0.21.1] - 2026-07-01

### Changed
- Removed the info icons from beside the metric-type choices on the metric form; the plain-language hint below the heading already explains the difference.

## [0.21.0] - 2026-06-30

### Changed
- **The check builder now speaks plain language and looks on-brand.** The rule and target pickers are a new branded, dark, keyboard-accessible dropdown (matching the theme instead of the browser's light native menu), rendered in the brand mono. The options read in plain English ("Contains a phrase", "Is valid JSON", "A JSON field equals a value", "The response text") instead of the raw `contains` / `valid_json` / `json_path_equals` / `response_text` identifiers, and the same human labels show on a check metric's page. Field labels and hints were reworded to plain language throughout.

## [0.20.4] - 2026-06-30

### Fixed
- **The new-metric form's type toggle now works (#93).** Choosing "LLM judge" vs "Deterministic check" previously did nothing and rendered both editors stacked, so a check could only be authored through the REST API or MCP. The chooser now shows only the selected editor and toggles the check builder's per-kind fields, and `create` strips the non-selected editor's fields server-side so a stray submission can never save both a rubric and a check config. Each type also gets a plain-language info icon, and the hint copy reads in plain terms.
- **Renamed the user-facing "judge-only run" wording to "score existing outputs" (#94).** Since check metrics landed, a scoring run can be entirely deterministic checks with no LLM judge, so the old label was a misnomer. The run form, status header, run-list badge, auto-generated run name, suggest-action alert, API reference, and MCP tool descriptions now describe scoring existing outputs instead. The internal `judge_only?` predicate is unchanged.
- **Documented the promptfoo import endpoint in the API reference (#95).** `POST /api/v1/imports/promptfoo` now has its own section in the in-app API reference, matching the other v1 resources, with its request forms and mapping-summary response.

## [0.20.3] - 2026-06-30

### Fixed
- **The check-metric UI now ships styled (#92).** Four class families used by the check-metric views had no rule in the engine stylesheet and rendered with browser defaults: the metric-type chooser radios (`ck-radio`), the check-builder field rows (`ck-field-row`), the judge-vs-check type chip (`ck-metric-type-chip`), and the check-spec display on a metric's show and index pages (`ck-check-spec` and its parts). They now render consistently with the rest of the metric UI, using the existing form, chip, and code conventions.

## [0.20.2] - 2026-06-30

### Fixed
- **The runs index and dashboard no longer show "Create your first run" when runs exist but are all hidden by `runs_display_scope` (#91).** The empty-state now checks the display-scope-free `Run.exists?` to tell a genuinely new workspace apart from one whose runs are all filtered out by run-history retention. A workspace with only hidden runs sees "Your older runs are hidden" instead of the misleading new-user call to action; a truly empty workspace still sees the new-user state, and the tag-filter empty state is unchanged.

## [0.20.1] - 2026-06-29

### Fixed
- **Dashboard stat aggregates and the metric suggest-button gates now honor `runs_display_scope` (#80).** The activity sparkline, worst-metric, failing-checks, failures, prompt-changes, metric-average, and metric-pass-rate aggregates, plus the agreement-disagreement counts behind the Suggest-improvements button (web, API), now exclude runs hidden by a host's run-retention scope, matching every other run-derived surface. With no `runs_display_scope` configured the behavior is unchanged.

## [0.20.0] - 2026-06-29

### Added
- **Import a promptfooconfig.yaml in one step (#76).** A new importer turns an existing Promptfoo config into CompletionKit records: inline `prompts` become a Prompt (their `{{var}}` templates map directly), `tests`/`vars` become a Dataset with one row per case, and `assert` blocks become Metrics. `llm-rubric` and `g-eval` map to a judge metric with the rubric text; `contains`, `icontains`, `not-contains`, `equals`, `regex`, and `is-json` map to deterministic check metrics; anything without an equivalent (a `javascript` assert, a prompt file reference, an unmatched provider) is reported as skipped with a reason rather than dropped. Available three ways: a web page (paste or upload, reachable from the metrics index), a REST endpoint (`POST /api/v1/imports/promptfoo`), and an MCP tool (`promptfoo_import`). This is a migration on-ramp for the eval and judge half of Promptfoo, not a claim of feature parity.

### Fixed
- **Response and Review broadcasts are now wrapped in `safely_broadcast` (#70), matching Run and ProviderCredential.** A failure while rendering or delivering one of those live-UI Turbo broadcasts is logged and swallowed instead of propagating into the saving job, so a cable-adapter hiccup or a future render regression can no longer turn a successful row write into a failed `GenerateRowJob` / `JudgeReviewJob`.

## [0.19.0] - 2026-06-29

### Added
- **Check metrics now render everywhere and gate run-vs-run comparison (#82, Release B).** Run and response surfaces show Pass/Fail badges and pass-rate pips for checks instead of star ratings, with the run list and status panel sorting failed checks first; check-only runs no longer show a judge "Avg score" framing, and the dashboard gains a failing-checks card. The run-vs-run comparison is now check-aware in both the HTML view and the v1 API: each per-metric row carries `kind`, `left_passed`/`right_passed`, and a `result_change` of `broke`, `fixed`, or `same`, so an automated pipeline polling the compare API catches a check that regressed from pass to fail (a valid-JSON response becoming invalid registers as `broke`, not an excluded error). The 1-5 rubric `avg_score` contract is unchanged; pass-rate stays a separate field.

## [0.18.1] - 2026-06-29

### Fixed
- **Run completion no longer depends on live judge-API validity.** A run's outstanding-work accounting and progress snapshot now decide which metrics are expected to produce reviews from the run's own `judge_model` intent plus its check metrics, rather than re-checking the provider's `valid_for_model?` at completion time. This removes an environment-dependent edge where a run could be counted differently depending on whether the judge API was currently reachable.

## [0.18.0] - 2026-06-29

### Added
- **Deterministic "check" metric type (#82).** A second metric type that evaluates a response with code instead of an LLM judge and yields pass/fail, alongside the existing 1-5 rubric judge. Eight check kinds ship: `contains`, `not_contains`, `equals`, `regex`, `valid_json`, `json_path_equals`, `length_bounds`, and `no_refusal`, each targeting the response text, the input row, or a json-path-extracted value. A `metric_type` discriminator and a serialized `check_config` land on metrics and metric_versions, and a nullable `passed` lands on reviews; `ai_score` stays NULL for checks, so checks are additive and never blend into the 1-5 averages. An unresolvable or malformed target records `passed: false` with a succeeded status (never an internal error), so a regression stays visible to CI. Checks run through a new non-LLM `CheckReviewJob`; a check-only run no longer hangs waiting on a judge, and a mixed run completes from its checks even when no judge is configured. `Run#check_pass_rate` is exposed in `Run#as_json` so automated pipelines can gate on check regressions from the v1 API. Check metrics can be authored through the form, the REST API, the MCP tools, and three new starters (Valid JSON, No refusal, Contains required token); `metric_type` locks once a metric has been used in a run. Because a check is exact, check metrics are excluded from the agreement/trust/suggest/judge-compare calibration machinery at every entry point. Run-list badges and the run-vs-run compare gate for checks follow in the next release.

## [0.17.1] - 2026-06-29

### Fixed
- **The dashboard now honors `runs_display_scope` like every other run surface (#81).** Its recent-runs list and the "Runs" stat-card count route through `Run.display_scoped`, and the recent-runs table now renders `runs_display_footer_partial` below it, so a host with run-history retention sees consistent visibility and its hidden-runs notice on the page users land on first. The stat-card visibility gate deliberately keys off the unscoped run total, so a long-tenured workspace whose runs have all aged past retention still sees its activity cards rather than a blank dashboard. Hosts that carried a `DashboardController#show` prepend to patch this can drop it.

## [0.17.0] - 2026-06-26

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
