# PII inventory across engine-owned tables

For hosts that need to support GDPR Article 20 (data portability) and
Article 17 (erasure), this is what lives in the tables the CompletionKit engine
owns. It is intentionally short because the picture is simple.

Audited against the engine schema as of `0.5.32`.

## Headline

**The engine has zero per-user identifiers.** No engine table has a
`user_id`, `created_by_user_id`, `assignee_user_id`, `owner_id`, or any
analogue. Multi-tenant attribution is the host's responsibility, layered on
through `CompletionKit.config.tenant_scope` and `tenant_scope_columns`
(documented in the README's "Multi-tenant host apps" section). With multi-tenant
configured, the host adds its own `organization_id` (or equivalent) to engine
tables via host-side migrations; without it, the engine runs single-tenant and
has no org concept at all.

Practically, this means:

- **There is no per-user data export from engine tables to assemble.** A user's
  content (e.g. a dataset they uploaded) is stored against the workspace, not
  against the individual user; the host's user/organization tables retain the
  attribution.
- **There is no per-user erasure to do in engine tables either.** Erasing a
  user does not change engine rows. If you want to remove the *content* a user
  contributed, that requires application-level intent (e.g. delete the
  datasets they uploaded), not an automatic cascade.

## Per-user identifier columns in engine tables

| Table | Per-user FK columns | Notes |
|---|---|---|
| every engine table | none | No `user_id` / `created_by_*` / `assignee_*` columns exist in any engine-owned table. |

## Content fields that may contain personal data

These are workspace-owned, not user-owned, but the *content* the host's users
put into them can include personal data. A host that operates under GDPR
should treat them as PII-carriers for export and deletion purposes, with the
caveat that they are scoped to an organization, not a single user.

| Table | Field | What it holds |
|---|---|---|
| `completion_kit_datasets` | `csv_data` | The raw CSV the host's user uploaded. May contain whatever the user put in it (names, emails, support tickets, etc.). |
| `completion_kit_responses` | `input_data` | The dataset row that drove this response. Derived from `csv_data`, same PII surface. |
| `completion_kit_responses` | `response_text` | The model's output for that row. May echo personal data present in the input. |
| `completion_kit_responses` | `expected_output` | Optional reference answer, host- or user-provided. |
| `completion_kit_reviews` | `ai_feedback` | The judge LLM's free-form feedback. May quote or paraphrase the input/response. |
| `completion_kit_prompts` | `template`, `description`, `name` | Free-form prompt copy. Usually not personal data, but a host with strict policies should treat free-text fields as potentially containing it. |
| `completion_kit_metrics` | `instruction`, `rubric_bands`, `name` | Free-form rubric text. Same caveat. |
| `completion_kit_runs` | `name`, `error_message`, `failure_summary` | Run label and provider error payloads. May leak content excerpts via provider errors. |
| `completion_kit_suggestions` | `original_template`, `suggested_template`, `reasoning` | Stored AI rewrite + its reasoning. May reference response content from the run it was generated against. |

Fields that are clearly **not personal data**: ids and FKs, status enums, model
metadata (`completion_kit_models`), tag names and colors
(`completion_kit_tags`, `completion_kit_taggings`), dashboard dismissals
(`completion_kit_dashboard_dismissals`), join positions, timestamps.

## Sensitive but not personal data

| Table | Field | Notes |
|---|---|---|
| `completion_kit_provider_credentials` | `api_key`, `api_endpoint` | Encrypted at rest via Active Record encryption. Org-level secret material (provider key), not user PII; treat as a workspace secret. |
| `completion_kit_mcp_sessions` | `session_id` | MCP session bearer. Org-level credential, not user PII. |

## Survival semantics

### When a user leaves an organization

No engine row changes. Engine tables have no per-user FK, so engine state has
no dependency on user membership. Whatever the user contributed to the
workspace (datasets, prompts, runs, …) belongs to the workspace and stays.

If the host wants user-level export ("everything *this user* put into this
workspace"), that attribution must come from the host's own audit/event log;
the engine does not record it.

### When an organization is deleted

This depends on whether the host is using the engine's tenant-scope hooks.

- **Multi-tenant host (cloud)** — the host has added a tenant column
  (typically `organization_id`) to each engine table via its own migrations.
  Cascading the org delete to engine rows is the host's responsibility. The
  recommended pattern: a single transactional purge of all engine tables
  filtered by `organization_id`, run as part of the host's org-delete job.
  Without this, engine rows are orphaned after org deletion.
- **Single-tenant host (the bundled standalone app, or any engine mount
  without tenant-scoping)** — there is no org concept in the engine and the
  "delete an org" operation does not exist. Engine rows persist until removed
  by the host or by direct database operations.

## Action items for hosts

1. **Export.** Aggregate engine rows scoped to the user's organization(s) for
   GDPR Art. 20. There is no need to filter by user inside the engine — the
   per-user attribution lives in the host's tables.
2. **Erasure.** A user erasure that requires removing personal data *content*
   the user contributed has to be modelled by the host: typically by tracking
   which datasets, prompts, and runs were created by each user (in the host's
   own audit table) and then deleting those engine rows.
3. **Org deletion.** If multi-tenant, run an org-scoped cascade across every
   `completion_kit_*` table in a single transaction. If the host has a "soft
   delete with N-day grace" model, the grace timer applies the same way to
   engine rows.

## Engine-side gaps

None identified that require engine code changes. The engine intentionally
holds no per-user attribution and exposes the tenant-scope hooks a host needs
to scope and cascade.
