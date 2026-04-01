# Async Model Discovery Design

Move model discovery from a synchronous `after_save` callback to a background job with real-time progress feedback via Turbo Streams. The progress component is reusable across provider credentials index, provider form, prompt model selects, and run judge model selects.

## Database Changes

Add three columns to `completion_kit_provider_credentials`:

| Column | Type | Default | Purpose |
|--------|------|---------|---------|
| `discovery_status` | string | nil | nil/discovering/completed/failed |
| `discovery_current` | integer | 0 | Models probed so far |
| `discovery_total` | integer | 0 | Total models to probe |

When `discovery_status` is nil, no discovery has run. When "discovering", progress is shown. When "completed" or "failed", the status displays briefly then resets on next save.

## Background Job

`ModelDiscoveryJob` at `app/jobs/completion_kit/model_discovery_job.rb`. Takes a `provider_credential_id`.

Flow:
1. Sets `discovery_status: "discovering"`, `discovery_current: 0`
2. Calls `ModelDiscoveryService#refresh!` with a progress callback
3. The callback updates `discovery_current` on the credential and broadcasts progress after each model probe
4. On success: sets `discovery_status: "completed"`, broadcasts completion (including model dropdown updates)
5. On error: sets `discovery_status: "failed"`, broadcasts the failure state

## Service Changes

`ModelDiscoveryService#probe_new_models` accepts an optional block. After probing each model, it yields the current count. The job passes a block that updates the credential's progress and broadcasts.

`ModelDiscoveryService#refresh!` also accepts the block and passes it through to `probe_new_models`. Before probing, it sets `discovery_total` on the credential to the count of unprobed models.

## ProviderCredential Model Changes

- `after_save :refresh_models` replaced with `after_save :enqueue_discovery`
- `enqueue_discovery` enqueues `ModelDiscoveryJob.perform_later(id)` for all providers (not just OpenAI)
- Add `broadcast_discovery_progress` — broadcasts replace to `discovery_status_#{id}` with the progress partial
- Add `broadcast_discovery_complete` — broadcasts replace to `discovery_status_#{id}` and all model select elements on the page
- Include `Turbo::Broadcastable`

## Reusable Progress Partial

`app/views/completion_kit/provider_credentials/_discovery_status.html.erb`

Takes a `provider_credential` local. Renders:
- Nothing when `discovery_status` is nil or "completed" (after brief display)
- Progress bar with "Discovering models... X/Y" when "discovering"
- Error message when "failed"

Wrapped in `div` with `id="discovery_status_#{credential.id}"` for Turbo Stream targeting.

Rendered in:
- Provider credentials index — inside each provider row
- Provider credential form — below the save button
- Prompt form model select — next to the dropdown
- Run form judge model select — next to the dropdown

## Model Select Updates

On discovery completion, Turbo Stream broadcasts replace model select elements with updated options. A shared model select partial wrapped in a targetable div enables this.

## Turbo Stream Broadcasts

From the job via the credential model:
- `broadcast_replace_to` targeting `discovery_status_#{id}` — updates progress bar during discovery
- On completion: additionally `broadcast_replace_to` targeting model select elements to refresh options with newly discovered models

Pages subscribe via `turbo_stream_from` for the credential's stream name.

## Testing

- Unit specs for `ModelDiscoveryJob` — sets status/progress, handles errors, sets "failed" on exception
- Unit specs for `ModelDiscoveryService` — progress callback yields current count during probing
- Unit specs for `ProviderCredential` — `enqueue_discovery` enqueues job on save, broadcast methods work
- Request specs for `ProviderCredentialsController` — create/update redirects immediately without blocking, index renders discovery status
- Update existing specs affected by callback change (sync to async)
- 100% line and branch coverage maintained
