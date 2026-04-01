# Refresh Models Modal & Multi-Provider Discovery

## Goal

Add a confirm + loading modal flow when refreshing models, persist Anthropic models in the registry alongside OpenAI, and update dropdowns in-place when probing completes.

## Flow

1. User clicks refresh icon next to model dropdown (prompt form or run form)
2. Browser `confirm()` dialog: "This will discover and probe models from all configured providers. This may take several minutes. Continue?"
3. If confirmed, modal overlay appears with spinner and "Discovering and probing models..."
4. AJAX fetch to `POST /completion_kit/refresh_models` (returns JSON)
5. Server discovers and probes models for ALL configured providers
6. Response JSON: `{ models_discovered: N, for_generation: N, for_judging: N, generation_options_html: "...", judging_options_html: "..." }`
7. Modal updates to "Done — X models discovered, Y for generation, Z for judging"
8. Dropdown `<select>` innerHTML replaced with updated options from response
9. Modal auto-closes after 2 seconds or on click

## ModelDiscoveryService — Anthropic Support

Currently only handles OpenAI. Add Anthropic:

- **Discovery:** `GET https://api.anthropic.com/v1/models?limit=100` with `x-api-key` and `anthropic-version` headers
- **Probing:** `POST https://api.anthropic.com/v1/messages` with a minimal message
  - Generation probe: `messages: [{role: "user", content: "Say hello"}]`, `max_tokens: 20`
  - Judging probe: structured Score/Feedback prompt, `max_tokens: 50`
- **Reconcile:** same logic — new models created as active, missing ones retired

Provider-specific methods in the service:
- `fetch_model_ids` — branches on `@provider` for API endpoint and headers
- `probe_generation` / `probe_judging` — branches on `@provider` for request format and response parsing

## Controller: refresh_all

`POST /completion_kit/refresh_models`

- If request accepts JSON (`format.json`): iterate all `ProviderCredential` records, run `ModelDiscoveryService.new(config: cred.config_hash).refresh!` for each, return JSON with counts and pre-rendered dropdown HTML
- If request is HTML: same but redirect back with flash (existing behavior)

## Frontend

- Refresh icon button gets `onclick` handler (inline JS)
- Confirm dialog before fetch
- Modal: fixed overlay, dark semi-transparent background, centered card with spinner and message
- On success: update dropdown, show completion stats, auto-close after 2s
- On error: show error message in modal, user dismisses manually
- Works identically on prompt form (generation dropdown) and run form (judge dropdown)

## Scope

- Anthropic discovery + probing added to ModelDiscoveryService
- Llama stays as-is (no model list API on self-hosted)
- refresh_all iterates all providers with credentials
- Modal is plain JS, no Stimulus
