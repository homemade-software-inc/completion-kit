# Review-grounded judging design

**Date:** 2026-05-30
**Status:** Approved, ready for implementation planning

## Goal

When the LLM judge scores an output, optionally show it a small set of past cases on the same metric where a human corrected its score. The examples are harvested automatically from calibration disagreements that people already record. No pinning, no manual curation. This reintroduces the few-shot signal that 0.9.0 removed, but sourced from reviews rather than a hand-picked set.

## Background

0.9.0 cut few-shot pinning entirely (commit `b1c8c8a`) because pinning overlapped with the metric-rewrite path and felt like busy-work. Both fed off the same disagreements list, and pinning added a separate manual step.

Two paths feed off human reviews. They are complementary, not redundant:

- **Rewrite (exists).** Disagreements teach a general rule, edited and published into the instruction or rubric. Permanent, version-controlled. Generalizes.
- **Examples (this design).** Disagreements ground specific cases the judge keeps getting wrong, injected at scoring time. Catches edge cases that are hard to write as a rule.

The loop this completes: run, review the misses, the next run's judge sees those corrections inline, fewer misses.

Most of the machinery already exists. A `Calibration` with a `disagree` verdict already captures `corrected_score` (required), `note`, `metric_version_id`, and `created_by`. `MetricCalibrationExamples` in `metric_variant_generator.rb` already selects recent disagreements for the current version and returns the row shape we need. The only thing 0.9.0 removed was the injection block in `JudgeService#build_judge_prompt` and the `human_examples:` parameter.

## Decisions and rationale

### Source: corrected-score-gated, which today means disagreements only

A case qualifies as a judge example only if it carries a `corrected_score`. In the current UI, only the `disagree` verdict lets a reviewer attach a score, so this resolves to disagreements today. The rule is future-proof: if scored borderlines are ever introduced, they qualify with no change to the selection logic.

Borderlines without a score are excluded. A borderline means "the rubric does not cleanly decide this." The right fix is to clarify the rubric, which is the rewrite path's job. A label-less example gives the judge nothing to copy and risks teaching it to cluster toward the middle, and the judge format ("Score: N, Feedback: one sentence") has no confidence channel for ambiguity to land in.

Agreements are excluded. The rubric is already a standing positive anchor in every prompt, and corrections shown as paired judge-versus-human scores already encode both directions, so a corrections-only set is not inherently a "score lower" lean. Positive anchors are held in reserve as a tuning lever if a corrections-only judge ever drifts in one direction.

### Scope: current metric version, no fallback

Examples come only from corrections recorded against the current metric version. On a freshly published version with no corrections of its own yet, inject nothing.

This is a deliberate divergence from `MetricCalibrationExamples`, which falls back to all versions when the current one has none. A correction labeled under a superseded rubric can mislabel under the new rubric. The rewrite path can afford the fallback because its output is a human-reviewed proposal. Runtime grounding silently affects every score, so it must not feed stale labels.

### Self-exclusion

Never feed a response's own correction into scoring that same response. Prevents trivial memorization and keeps the agreement stat meaningful.

### Cap: most recent 5

A constant for v1, not a config knob. Runtime injection multiplies across every scored output in every run, so the set is kept small. Configurability is deferred.

### Control model: automatic and visible

Examples flow automatically. The metric page surfaces which cases are active and lets the operator mute a bad one. No pinning, no scores to enter.

### Default: separate flag, off

New `judge_examples_from_reviews`, default false, meaningful only when `judge_calibration_enabled` is on. Off by default so the bare-judge agreement baseline stays honest until the operator opts in. The intended sequence: enable calibration, measure the raw judge, review the misses, turn grounding on, watch agreement improve. Defaulting on would contaminate that baseline from day one, because the agreement stat would then reflect "judge plus its own past corrections" rather than the bare judge.

## Components

### Selection (new method, separate from the rewrite path)

A new selection method returns the runtime example set. Kept separate from `MetricCalibrationExamples` so the rewrite path's fallback behavior stays untouched.

Inputs: the metric, the response being scored (for self-exclusion), a limit.

Query: calibrations on the metric where `corrected_score` is present and `excluded_from_examples` is false, scoped to `MetricVersion.current` for the metric, excluding the response being scored, ordered most recent first, limited to 5. If the current version has no qualifying corrections, return an empty set. No fallback.

Returns the existing row shape: input, output, judge score, judge feedback, human score, human note.

### Judge prompt injection

`JudgeService#evaluate` and `build_judge_prompt` regain an optional `human_examples:` parameter. When present, a block is injected between the rubric and the output to evaluate, the slot the 0.9.0 removal vacated.

Each example renders as a paired correction, for example:

```
Output: <truncated to ~200 chars>. The judge scored this 4/5. A reviewer corrected it to 2/5: <note truncated to ~160 chars>.
```

Paired scores keep the set from reading as one-directional. When `human_examples:` is absent or empty, the prompt is byte-identical to today's.

### Job wiring

`JudgeReviewJob#perform` fetches the example set when `judge_examples_from_reviews` and `judge_calibration_enabled` are both on, passing the response being scored so it can be self-excluded, and hands the set to `JudgeService#evaluate`. When either flag is off, it passes nothing.

### Config

Add `judge_examples_from_reviews` to `Configuration`, default false.

### UI

On the metric show page, inside the Calibration card and rendered only when `judge_examples_from_reviews` is on, a compact "Guiding the judge" section lists the active cases (the same set the judge sees) with a small exclude icon on each. Excluding sets `excluded_from_examples` and updates the page over Turbo Streams. That is the entire control surface.

### Data model

One new column: `excluded_from_examples` boolean on `completion_kit_calibrations`, default false, not null.

Migration lives in the engine `db/migrate/`, is installed into `standalone/` via `completion_kit:install:migrations`, and the inline test schema in `spec/rails_helper.rb` is updated to match.

## Data flow

1. A run scores a response. `JudgeReviewJob#perform` runs for the response and metric.
2. If grounding is on, the selection method returns up to 5 recent corrections for the current metric version, excluding this response and any muted cases.
3. `JudgeService` injects them between the rubric and the output.
4. The LLM scores the output with the corrections in context.

## Edge cases and error handling

- Flag off, or calibration disabled: no examples, behavior identical to today.
- Fresh version with no current-version corrections: empty set, no fallback.
- All qualifying cases muted, or none exist: empty set.
- The response being scored has its own correction: excluded from its own example set.
- Long inputs, outputs, and notes: truncated to bound token cost.

## Out of scope

- Borderlines without a score.
- Agreement anchors.
- Similarity-based retrieval of relevant examples. Recency only for v1.
- A configurable cap.

Each is a later lever if a real need appears.

## Testing

RSpec and FactoryBot, 100% line and branch coverage:

- Selection: current-version scoping, no fallback on a fresh version, self-exclusion, muted-case exclusion, the cap, and the corrected-score gate.
- Prompt injection: block present when examples are given, absent when not, paired format correct.
- Job wiring: examples passed when both flags on, not passed when either is off.
- Config: `judge_examples_from_reviews` defaults to false.
- UI: the exclude action sets the flag and the section renders only when grounding is on.

## Touchpoints

- `app/services/completion_kit/judge_service.rb` (`evaluate`, `build_judge_prompt`)
- `app/jobs/completion_kit/judge_review_job.rb` (`perform`)
- `app/services/completion_kit/metric_variant_generator.rb` (new sibling selection method, or a small new selection object)
- `app/models/completion_kit/calibration.rb`
- `lib/completion_kit.rb` (`Configuration`)
- `app/views/completion_kit/metrics/show.html.erb` and the Calibration card partial
- `db/migrate/` plus the standalone install and `spec/rails_helper.rb` inline schema
