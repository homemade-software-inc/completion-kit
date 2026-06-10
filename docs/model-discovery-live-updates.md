# Model-discovery live updates: broadcasts + poll (complementary, not redundant)

Provider model-discovery progress reaches the browser through **two mechanisms on purpose**. They cover different surfaces; removing either regresses the others. This is the answer to "can't we just use broadcasts as the source of truth and drop the poll?" (issue #64) — no.

## The two paths

**Turbo broadcasts** (worker → Action Cable) — `ProviderCredential#broadcast_discovery_progress` / `#broadcast_provider_models` / `#broadcast_model_dropdowns`, each wrapped in `safely_broadcast` (log-and-continue):

- Low-latency live updates while a `bin/jobs` worker probes models.
- The **only** source of the generation/judge dropdown option lists (`prompt_llm_model` / `run_judge_model`) on open prompt/run forms. The poll never touches these.

**The `statuses` poll** (browser → `provider_credentials#statuses`, driven by `app/assets/javascripts/completion_kit/application.js`) re-renders `discovery_status_#{id}` and `provider_models_#{id}` from persisted state in request context:

- **Self-heal** — a page loaded mid-discovery shows current state. Turbo has no replay, and solid_cable's retention only buffers messages published *after* subscribe.
- **Grace bridge** — the ~8s window after a refresh click, before the async job's first broadcast lands.
- **Missed-tick recovery** — reconciles any broadcast lost to a reconnect, a cable hiccup, or a `safely_broadcast`-swallowed render error.
- **Index convergence** — the providers index has no `provider_models_#{id}` element, so the broadcast morph is a no-op there; the poll's `discovery_status` replace is what flips an index card to "completed".

## Why both stay

- Retiring **broadcasts** → open forms stop getting live dropdown updates.
- Retiring the **poll** → loses self-heal, the grace bridge, missed-tick recovery, and index completion convergence. Worker partial-render broadcasts also have a documented production failure mode (commit `f017b56`): they can silently publish nothing even when the cable relay works, and delivery (worker → DB → web → browser) is not covered by any test — CI uses the `test` cable adapter and specs mock the broadcast calls.

Note: the broadcast partials are safe to render on a bare host (no `default_url_options` shim) — they use only `_path` helpers, which don't read `default_url_options[:host]`. The `:org_slug UrlGenerationError` in issue #64 only hits a *direct* route-helper call, not the render path.

If broadcast-only is ever revisited, gate it on real end-to-end evidence (a connected browser receiving Turbo streams from a real `bin/jobs` worker against the production cable adapter) plus a system spec, and fold the dropdown replacement into a subscribe-time snapshot.
