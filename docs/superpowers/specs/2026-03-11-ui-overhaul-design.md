# CompletionKit UI Overhaul

## Goal

Redesign every view in the CompletionKit engine to fix inconsistent layouts, broken navigation, confusing terminology, irrelevant buttons, and a data model that conflates unrelated concerns. The result should be a clean, navigable UI that mirrors how people actually use the tool.

## Data Model Changes

### Current → New

The current model has `Prompt` holding template, generation model, judge model, and metric group. CSV data is inlined on `TestRun`. `TestResult` conflates the AI response with review scores. Terminology uses "output," "test run," "test result," and "evaluate."

The new model separates these concerns:

### Prompt

Template + generation model. Versioned, publishable. No judge config.

Fields kept: name, description, template, llm_model, version_number, published_at, family_key, current.

Fields removed: assessment_model (→ Run.judge_model), metric_group_id (→ Run.metric_group_id).

Fields dropped: review_guidance, rubric_text, rubric_bands (these were pre-metric-redesign fields, superseded by the Metric model's criteria + rubric).

Has many runs.

### Dataset

Named, reusable CSV. Own entity with own nav tab. Decoupled from runs — the same dataset can be used across many runs and prompts.

Fields: name, csv_data.

Used by many runs.

### Run

One test of a prompt against a dataset. Optionally includes judge config.

Fields: prompt_id, dataset_id, judge_model (optional, string), metric_group_id (optional, references MetricGroup), status, created_at.

Metric selection uses metric_group_id only (same pattern as current, just moved from Prompt to Run). No individual metric selection — users pick a group.

Statuses: `pending` (created, not yet executed), `generating` (LLM producing responses), `judging` (judge scoring responses), `completed` (all done), `failed`.

Auto-named: "{prompt name} v{version_number} — {timestamp}".

Has many responses.

### Response

One dataset row run through the LLM. Replaces the current `CompletionKit::TestResult` model.

Fields: run_id, input_data, response_text, expected_output.

`expected_output` is denormalized from the dataset row at generation time (same as current behavior). This avoids needing to re-parse the CSV to display results.

Has many reviews (one per metric).

### Review

The judge's assessment of one response for one metric. One record per response per metric (same cardinality as the current `CompletionKit::TestResultMetricAssessment` model, renamed).

Fields: response_id, metric_id, metric_name, criteria, ai_score (integer 1-5), ai_feedback (text).

No human review fields (human_score, human_feedback dropped).

## Execution Flow

1. User creates a run: picks prompt (template + model), picks dataset, optionally configures judge (model + metric group).
2. System executes: each dataset row goes through the LLM → creates a Response (input + response_text). Run status: `generating`.
3. If judge config exists: each response goes through the judge → creates Reviews (one per metric per response). Run status: `judging`, then `completed`.
4. If no judge config: run completes after generation. Status: `completed`.
5. "Judge responses" action available on completed runs without judge config — opens a form to pick judge model + metric group, then runs the judge. This updates the run's judge_model and metric_group_id, sets status to `judging`.

Backend keeps generation and judging as separate operations, but the UI chains them when both are configured upfront — user clicks "Run test" once, both run sequentially.

## Terminology Changes

| Old | New |
|-----|-----|
| output / output_text | response / response_text |
| test run (`CompletionKit::TestRun`) | run (`CompletionKit::Run`) |
| test result (`CompletionKit::TestResult`) | response (`CompletionKit::Response`) |
| csv_data (on test run) | dataset (`CompletionKit::Dataset`, separate model) |
| evaluate / AI review | judge (verb) |
| quality_score | score (avg of review ai_scores, computed) |
| assessment_model (on Prompt) | judge_model (on Run) |
| metric_assessment (`CompletionKit::TestResultMetricAssessment`) | review (`CompletionKit::Review`) |
| Providers (nav) | Settings |
| human_score / human_feedback | dropped |

## Routes

```ruby
root to: "prompts#index"

resources :prompts do
  member do
    post :publish
    post :new_version
  end
end

resources :datasets
resources :metrics
resources :metric_groups

resources :runs do
  member do
    post :generate    # generate responses from LLM
    post :judge       # run judge on responses (replaces :evaluate)
  end
  resources :responses, only: [:show]
end

resources :provider_credentials, only: [:index, :new, :create, :edit, :update]
```

Runs and responses use flat top-level routes (not nested under prompts) for simplicity. Breadcrumbs provide the navigational context back to the prompt.

## Navigation

Top nav: **Prompts · Metrics · Datasets · Runs · Settings**

- Prompts is the engine home (root route).
- Metrics: metrics + metric groups.
- Datasets: named, reusable CSV datasets.
- Runs: all runs across all prompts (cross-prompt overview).
- Settings: provider credentials.

## Page Map

```
Prompts index          — engine home, table of prompts
  Prompt show          — THE HUB: template, model, runs table, versions
    Prompt new/edit    — template + model only (no judge config)
  Run show             — responses + review, accessed via prompt
    Response show      — full response + review detail

Metrics index          — table of metrics + link to groups
  Metric show/new/edit
  Groups index/show/new/edit

Datasets index         — table of datasets
  Dataset show         — CSV preview, which runs use it
  Dataset new/edit

Runs index             — all runs across all prompts (table)

Settings               — provider credentials (table)
```

## Page Designs

### Prompts Index (Engine Home)

Table layout. Columns: Name, Model, Runs, Last run, →.

Click row to open prompt. One action button: "New prompt."

### Prompt Show (The Hub)

This is where users spend most of their time. Single column layout.

**Header**: Prompt name + version badge (e.g. "v3 · current") + model.

**Actions**: Edit (secondary), New version (secondary), Run test (primary).

**Sections**:
- **Template**: code block showing the prompt template.
- **Runs**: table with columns Run (auto-name), Responses (count), Avg score (badge, or "—" if no judge config), →. Score trajectory is visible across rows — users can see improvement across versions.
- **Versions**: horizontal list of version chips. Current version highlighted. Clicking a non-current version navigates to that version's prompt show page (using the prompt's ID, since each version is its own Prompt record linked by family_key).

**"Run test" form**: Opens the run new page with the prompt pre-selected. Form fields:
- Dataset: select from existing datasets, or link to create a new one.
- Judge model: select (optional). Shows available models from provider credentials.
- Metric group: select (optional). Only shown if judge model is selected.
- If no datasets exist, the form shows a message with a link to create one first.

### Run Show

Accessed from prompt show. Breadcrumb: Prompts → {Prompt} → {Run name}.

**Header**: Auto-generated name (e.g. "Support Agent v3 — Mar 11, 15:48").

**Meta line**: Model, Dataset (linked), Judge model + Metrics (if configured), or "No judge configured."

**Collapsible**: Dataset preview (rows).

**Primary action**: "Judge responses" (only shown when run is completed and has no judge config). This opens an inline form or modal with judge model select + metric group select, then submits to the `judge` action.

**Responses section**: Summary cards (not table rows). Each card shows:
- Row number
- Input preview (truncated)
- Response preview (truncated)
- Score badge + metric pips (if judged)

Cards for low scores get a subtle red border tint. Click card to open response detail.

Sort controls: Best first / Worst first (only when judged).

**Run without judge**: Same cards but without score/metrics. Just row number, input preview, response preview. "Judge responses" as primary action.

**Run in progress**: Show status indicator (generating/judging) with response count progress.

### Response Show

Accessed from run show. Breadcrumb: Prompts → {Prompt} → {Run} → Response #{n}.

**Header**: "Response #1" + score badge (if reviewed).

**Sections** (stacked, generous spacing):
- **Input**: code block with JSON input data.
- **Response**: the AI response text.
- **Expected** (if present): expected output + similarity %.

**Review section** (if judged): Per-metric cards, each showing:
- Metric name + star rating (1-5)
- AI feedback text

No human review section.

### Datasets Index

Table layout. Columns: Name, Rows, Used in (count of all runs referencing this dataset), Created, →.

One action button: "New dataset."

### Dataset Show

Breadcrumb: Datasets → {Name}.

Header with name. Edit action (secondary).

Sections:
- CSV data preview (code block or table).
- Runs using this dataset (table with links to each run).

### Dataset New/Edit

Form: name + CSV data textarea.

### Metrics Index

Table layout. Columns: Name, Criteria (preview), Group, →.

Actions: "New metric" (primary), "Groups" (secondary, links to groups index).

### Metric Show

Single column. Criteria, evaluation steps, star rubric. No sidebar.

### Metric Groups

Groups index: table of groups. Group show: group name, description, member metrics listed.

### Runs Index (Cross-prompt)

Table layout. Columns: Run (auto-name), Prompt (linked), Responses, Avg score, →.

No "New run" button — runs are created from the prompt page.

### Settings

Provider credentials table. Columns: Provider, Status (connected/not), Endpoint, →.

Actions: "New provider."

## Global Rules

### Layout
- Tables for all index pages.
- Cards for responses on the run page.
- Single column for all detail/show pages (no sidebar layouts).
- Generous spacing throughout — more whitespace than current.
- Collapsible sections for secondary content (dataset preview, etc.).

### Buttons
- One primary action per page (dark button).
- No duplicated buttons across header and body.
- Actions must be relevant to the page they're on.
- "Judge responses" not "Add review" or "Run AI review."
- Destructive actions require confirmation.

### Navigation
- Breadcrumbs on every sub-page, matching nav terminology.
- Click table row or card to navigate.
- Active nav tab highlighted.
- Consistent breadcrumb trail: Prompts → {Prompt} → {Run} → Response #{n}.

### Terminology
- "Response" not "output" everywhere.
- "Run" not "test run."
- "Judge" as the verb for scoring.
- "Dataset" as own entity.
- "Settings" not "Providers."

## What Gets Removed

- Card-based index pages (all become tables).
- Sidebar layout on prompt show.
- Human review form and all human_score/human_feedback fields.
- Two-step "generate then evaluate" — single "Run test" action chains both.
- Duplicate buttons (e.g. "Run AI review" appearing on both run and result pages).
- Orphan test results index page (responses live on the run page).
- Inline CSV on runs (replaced by dataset reference).
- assessment_model and metric_group_id on Prompt model (moved to Run).
- review_guidance, rubric_text, rubric_bands on Prompt (superseded by Metric model).
- "Output" terminology everywhere.

## What Gets Added

- Dataset as first-class entity with own nav tab and CRUD.
- Prompt show as the hub with runs table showing score trajectory.
- Response summary cards on run page.
- "Judge responses" action for runs without judge config.
- Consistent table layouts across all index pages.
- Auto-naming for runs.
- New run statuses: pending, generating, judging, completed, failed.

## Migration Path (Data Model)

1. Create `CompletionKit::Dataset` model (name, csv_data). Add migration.
2. Add `dataset_id` to `test_runs` table. Migrate existing `csv_data` into Dataset records and link them.
3. Add `judge_model` (string) and `metric_group_id` (integer) to `test_runs` table. Migrate values from associated prompts.
4. Remove `assessment_model` and `metric_group_id` from `prompts` table.
5. Remove `review_guidance`, `rubric_text`, `rubric_bands` from `prompts` table (if still present).
6. Rename `test_runs` table → `runs` (or keep table name and just rename the model class).
7. Rename `test_results` table → `responses`, rename `output_text` column → `response_text`.
8. Rename `test_result_metric_assessments` table → `reviews`. Drop `human_score` and `human_feedback` columns.
9. Drop `quality_score` from responses (computed from review ai_scores on the fly).
10. Update `status` enum on runs: `pending`, `generating`, `judging`, `completed`, `failed`.
11. Remove `csv_data` column from runs table (now on Dataset).
12. Update all routes, controllers, views, and service classes to use new names.
