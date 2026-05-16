# Dismissible Dashboard Alerts — Design

**Goal:** Let the user ignore items on the standalone dashboard's worst-metric and failures
cards, with a per-card flyout to review and un-ignore what's been dismissed.

## Problem

The dashboard surfaces alerts (worst metric, failed reviews) with no way to acknowledge
them. A known-and-fixed metric keeps occupying the card; an old failure keeps counting.
The "Failed reviews" card is also arbitrarily narrow — it counts only judge-review
failures and ignores run failures and per-row generation failures.

## Scope

Two ignorable surfaces:

1. **Worst-metric card** — ignore a metric.
2. **Failures card** — a unified rewrite of "Failed reviews"; ignore individual failures.

Activity and prompt-changes cards are unchanged — they are informational, not alerts.

## Failures card — unified rewrite

The narrow "Failed reviews" card becomes a **Failures** card covering all three failure
surfaces over the trailing 7-day window:

| Surface | Source | Deep link | Cause shown |
|---|---|---|---|
| Run failed | `Run.status = "failed"` | run | `failure_summary` |
| Generation failed | `Response.status = "failed"` | response | `error_provider` / `error_class` |
| Judge failed | `Review.status = "failed"` | response (via review) | `error_provider` / `error_class` |

The card shows a total count and expands into a triage list grouped by surface. Each row
shows the cause and a dismiss (×) control. Empty state: "All clear — nothing failed
this week."

## Data model

New engine table `completion_kit_dashboard_dismissals`, model
`CompletionKit::DashboardDismissal`:

- `dismissable_type` (string) / `dismissable_id` (integer) — polymorphic; points at a
  `CompletionKit::Metric`, `Run`, `Response`, or `Review`.
- `baseline_score` (decimal, precision 4, scale 1, nullable) — metric dismissals only:
  the average judge score snapshotted at ignore time.
- `created_at` / `updated_at`.
- Unique index on `[dismissable_type, dismissable_id]`.

The migration ships from the engine and installs into the standalone app via
`completion_kit:install:migrations`.

## Behaviour

### Worst metric

`DashboardStats.worst_metric` switches from grouping by `metric_name` to `metric_id` so
dismissals can be matched.

- Ignoring a metric creates a dismissal with `baseline_score` = the metric's current
  window average.
- `worst_metric` excludes a dismissed metric **while its current average holds at or
  above `baseline_score`**.
- If the metric's average regresses **below** `baseline_score`, it resurfaces, and the
  stale dismissal is deleted — so re-ignoring it re-snapshots a fresh baseline.
- The card always picks the worst *non-dismissed* metric, so a genuinely-worse other
  metric surfaces on its own.

### Failures

A failure is a finished past event — it cannot un-fail — so a failure dismissal is
permanent until the user un-ignores it. Dismissed failures drop out of both the count
and the triage list. Dismissals are not auto-expired by the rolling window.

## UI — per-card flyout

Each of the two cards gets a small "N ignored" toggle. It expands a flyout listing that
card's dismissed items, each with an un-ignore button:

- Worst-metric flyout: ignored metrics, each showing its name and baseline score.
- Failures flyout: ignored failures, each showing surface + cause.

The toggle is hidden when nothing is ignored for that card.

All ignore and un-ignore actions update the dashboard via Turbo Streams — no page
reload.

## Plumbing

- **Engine:** `DashboardDismissal` model, migration, `DashboardStats` changes —
  `worst_metric` dismissal filter, new `failures(since:)`, removal of
  `failed_review_count`.
- **Standalone:** `DashboardDismissalsController` (`create` / `destroy`), routes, flyout
  partials, Turbo Stream templates; `HomeController` swaps `@failed_review_count` for
  `@failures`.

## Testing

- Model spec for `DashboardDismissal` (validations, polymorphic association).
- `DashboardStats` specs: `worst_metric` excludes dismissed, resurfaces on regression,
  clears stale dismissal; `failures` aggregates three surfaces and excludes dismissed.
- Controller specs for create/destroy of both dismissal kinds.
- 100% line and branch coverage maintained — CI-enforced.

## Out of scope

- Dismissing activity or prompt-changes cards.
- A central cross-card "ignored items" page.
- Auto-expiry of failure dismissals.
