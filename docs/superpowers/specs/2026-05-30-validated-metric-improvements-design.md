# Validated metric improvements (and the Agreement reframe)

**Date:** 2026-05-30
**Status:** Drafted in brainstorming, pending review

## Goal

Make "improve the metric from human reviews" genuinely trustworthy, even when there are only a few reviews, by validating every suggested change against the user's own reviewed cases and showing a before/after scoreboard before they publish. Reframe the surrounding "calibration" concept in plain language so an average user understands it.

## Why

Two problems with the current calibration / improve-metric feature:

1. **"Calibration" is jargon.** It is borrowed from ML and does not tell an average user what the thing is for. What it actually measures is plain: how often the automated judge lands on the same score the user would.
2. **The improve step overpromises on thin data.** Rewriting an instruction and rubric from one to three disagreements is reacting to anecdotes. The model returns a confident-looking rewrite that overfits those cases and may quietly regress on cases the user never reviewed. The draft → diff → publish flow is the right shape, but "improve the metric" at one disagreement oversells it.

The feature's primary job is the **improvement engine**: turning human corrections into a better metric over time. The agreement measurement is the means (it surfaces what to fix and grades whether a fix helped), not the headline.

## Mental model: your reviews are an answer key

- A user's reviews are cases they graded themselves. Collectively they are an **answer key**.
- **Agreement** = the share of answer-key cases where the judge lands on the user's score. This is the plain-language replacement for "calibration".
- **Improving the metric** = finding a version of the instruction and rubric that matches the answer key better.
- Every suggested improvement is **scored against the answer key before publishing**. The user sees "matches you on 1 of 5 today → 4 of 5 with this change; fixes 3, breaks 1," and never publishes on faith.

Two payoffs: the "limited reviews" worry becomes self-answering (the denominator is shown, the user judges for themselves), and "calibration" stops being a standalone concept to learn — it is just the scoreboard an improvement tries to move.

## The Agreement reframe (naming and copy)

Retire "Calibration" from user-facing copy (it may stay in code/internals).

- Section kicker: **Agreement** (replaces "Calibration").
- One-liner: "How often the judge lands on the same score you would. Review its scores to build that, and improve the metric to raise it."
- Measured-state stat leads with the plain figure: "Agrees with you on ~80% of 25 reviews." The sample size stays. The statistical tokens (Margin ±pt, Read: settled/early) are trimmed in favor of the plain sentence; the borderline/"Unclear" rate may stay as a secondary chip if useful. This keeps the average-bear read clean.
- The not-measured and counter states keep the version-named copy shipped in 0.10.0 ("v2 needs 10 human reviews…").

## The validation mechanic

### Answer key

The answer key is the set of reviewed cases for the metric **on its current version**. A review given under an older version endorsed a score under that version's rubric, so it is not a fair grader for a candidate built from the current one. Each entry carries the user's position:

- Disagreement → position = the corrected score the user gave.
- Agreement → position = the score the user endorsed (the judge's score at review time).
- Borderline → excluded from the tally (shown as a count, not graded).

Cap the answer key at the **30 most recent** reviewed cases; if capped, say so ("tested against your 30 most recent reviews").

### Flow when the user clicks Suggest improvements

1. Generate a candidate instruction + rubric from the current-version disagreements (today's `MetricVariantGenerator`, unchanged) and create the draft `MetricVersion`.
2. Re-score every answer-key case with the candidate's instruction + rubric, reusing `JudgeService` against each response's text and input data.
3. Compare each new score to the user's position (exact-score match) and tally:
   - **Fixes** — disagreements the candidate now matches.
   - **Keeps** — agreements still matched.
   - **Breaks** — agreements the candidate now misses.
   - **Still off** — disagreements it still does not match.
4. Compute before/after agreement: before = (agreements) / (answer-key size); after = (candidate matches) / (answer-key size).

### Honesty rules

- **Exact-score match** for the tally (a 3-vs-4 near-miss is not a match; that drift is the point). Show the actual scores per case so a close miss reads as close.
- **"Breaks" is the load-bearing signal.** The candidate was written from the disagreements, so fixing them is near-automatic. What matters is what it does to the agreements it was not built for. A candidate that fixes 3 but breaks 4 is worse, and the scoreboard says so.
- Re-scoring is one LLM pass per case, so the board is **indicative, not a proof**; the user is eyeballing the diff anyway.

## Architecture

- Re-scoring N cases is N+1 LLM calls, too much to block a request. Run generation + validation as **one background job** on Solid Queue (the existing judging queue), and **Turbo-stream** the scoreboard onto the page when it lands (no reload). Show a pending state meanwhile: "Drafting a candidate and testing it against your N reviews…"
- Re-scoring **reuses `JudgeService`** with the candidate's instruction + rubric; no new judging path.
- **Storage:** a JSON summary on the draft `MetricVersion` (the tally, before/after agreement, and the per-case rows: response id, user position, candidate score, outcome). One migration. The summary survives reloads and bridges the async gap.

## UX placement

- The scoreboard belongs to the candidate (the draft), so it appears in the existing compare-before-publish surface: the **diff modal**. A verdict line sits at the top — "Matches you on 4/5 (was 1/5). Fixes 3, breaks 1." — above the instruction/rubric diff, with Publish / Edit / Discard beneath.
- A compact figure ("4/5") rides on the draft's row in the Versions table.
- Publish stays a human decision. If the candidate is **net-negative** (matches less, or breaks more than it fixes), the publish button warns: "This agrees with you less than the current version. Publish anyway?" It does not hard-block.

## Edge cases and error handling

- **Only disagreements, no agreements** in the key → scoreboard shows Fixes / Still-off, no Keeps / Breaks. The denominator tells the truth.
- **A re-score errors out** on a case → skip it; report "tested N of M" rather than failing the board.
- **Candidate will not generate** (model returns nothing usable) → today's "no usable variants" alert, no scoreboard.
- **>30 reviewed cases** → test the 30 most recent and say so.
- **Net-negative candidate** → publish allowed with the warning above.
- **A reviewed response since deleted or with no text** → not part of the answer key (can only score responses with text and a verdict).
- A draft already pending → the Suggest button is hidden (today's behavior); one candidate at a time.

## Out of scope

- Making the reviewer's note/reason required or the primary rewrite input (Approach 2 from brainstorming) — not chosen now.
- Re-running re-scores multiple times for statistical stability.
- Any change to review-grounded judging (shipped in 0.10.0) or to the candidate generator itself.

## Testing

RSpec and FactoryBot, 100% line and branch:

- The tally logic with stubbed judge scores: fixes / keeps / breaks / still-off and before→after agreement, exact-match.
- The background job: generates the candidate, stores the summary on the draft, broadcasts.
- Scoreboard render in the diff modal and the compact figure on the version row.
- Each corner: only-disagreements (no keeps/breaks), borderline excluded, capped at 30, re-score failure skipped, net-negative publish warning, candidate-generation failure.
- The Agreement copy reframe (section kicker, one-liner, measured-state figure) and that "calibration" is gone from the rendered page.

## Touchpoints

- `app/services/completion_kit/metric_variant_generator.rb` (reused for candidate generation; the validation likely a new sibling service)
- New: a validation service that re-scores the answer key and builds the tally, and a background job to run generate + validate
- `app/services/completion_kit/judge_service.rb` (reused for re-scoring)
- `app/models/completion_kit/metric_version.rb` + a migration for the JSON validation summary on drafts
- `app/controllers/completion_kit/metrics_controller.rb` (`suggest_variants` becomes enqueue + pending state)
- `app/views/completion_kit/metrics/show.html.erb` (Agreement reframe, draft-row figure) and the diff modal (scoreboard verdict line, net-negative publish warning)
- `app/views/completion_kit/calibrations/_trust_panel.html.erb` (Agreement copy)
- `app/assets/stylesheets/completion_kit/application.css` (scoreboard styles)
