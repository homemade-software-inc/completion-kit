# Onboarding concept tips — design

## Goal

Add inline info popovers ("tips") to the onboarding empty state so a new user
can learn the core CompletionKit concepts in context, without leaving the page.

## Context

The onboarding empty state is rendered by `standalone/app/views/home/index.html.erb`
in its `<% else %>` branch (shown until a provider, a prompt, and a run all
exist). It contains three step cards:

1. **Configure a provider**
2. **Create a prompt**
3. **Run an evaluation**

Each card is a `.ck-card` with a `.ck-step` kicker, a `.ck-section-title`
heading, a `.ck-copy` paragraph, and a link button.

The app already has a JS-free popover pattern: `.ck-flyout`, a native
`<details>`/`<summary>` disclosure styled as a floating panel (used by the
dashboard's ignored-metrics flyout, defined in the engine stylesheet
`app/assets/stylesheets/completion_kit/application.css`). The new tips reuse
this `<details>` mechanism.

## Scope

Inline ⓘ tips on concept terms within the three existing step cards. One ⓘ per
concept. No dedicated concepts card. Six concepts are covered:

| Concept | Step | Term in copy |
|---|---|---|
| Provider Credential | 1 | "provider" |
| Prompt | 2 | "prompt" |
| Dataset | 3 | "dataset" |
| Run | 3 | "Run" |
| Response | 3 | "responses" |
| Metric | 3 | "metrics" (added by reword) |

Metric Group and Tag are intentionally excluded — they are not relevant to
onboarding and forcing them into the copy would bloat it.

### Step 3 reword

Current copy:

> Run your prompt against a dataset and score the responses with a judge model.
> Compare results across prompt versions.

New copy:

> Run your prompt against a dataset and score the responses against metrics you
> define, with a judge model. Compare results across prompt versions.

This introduces the word "metrics" so the Metric concept has a term to attach
to. No other copy changes.

## Components

### 1. Concept definitions — `standalone/app/helpers/home_helper.rb`

A `CONCEPTS` hash keyed by symbol, each value carrying a display `name` and a
one-line `definition`. Wording is condensed from the README "Concepts" section.

```ruby
module HomeHelper
  CONCEPTS = {
    provider_credential: {
      name: "Provider Credential",
      definition: "An API key for a model provider such as OpenAI or Anthropic. Encrypted at rest and never returned through the API."
    },
    prompt: {
      name: "Prompt",
      definition: "A versioned template with {{variable}} placeholders. Editing a prompt that has already been run creates a new version, so past results stay reproducible."
    },
    dataset: {
      name: "Dataset",
      definition: "A CSV of real inputs. Each row becomes one test case."
    },
    run: {
      name: "Run",
      definition: "One execution of a prompt against a dataset. Stores every output and the judge's scores."
    },
    response: {
      name: "Response",
      definition: "The model's output for a single dataset row, with the judge's reviews attached."
    },
    metric: {
      name: "Metric",
      definition: "An evaluation dimension with its own 1-5 rubric. The LLM judge scores every response against it."
    }
  }.freeze
end
```

### 2. Partial — `standalone/app/views/home/_concept.html.erb`

Renders a concept term followed by its tip. Locals:

- `term:` — the display word as it reads in the sentence (e.g. `"provider"`,
  `"Run"`).
- `key:` — the `CONCEPTS` key (e.g. `:provider_credential`).

Markup shape:

```erb
<%# locals: term, key %>
<% concept = HomeHelper::CONCEPTS.fetch(key) %><span class="ck-concept"><%= term %><details class="ck-concept__tip">
  <summary class="ck-concept__toggle" aria-label="What is a <%= concept[:name] %>?">
    <%= heroicon_tag "information-circle", variant: :outline, size: 14, class: "ck-concept__icon", "aria-hidden": "true" %>
  </summary>
  <div class="ck-concept__pop" role="tooltip">
    <p class="ck-concept__name"><%= concept[:name] %></p>
    <p class="ck-concept__body"><%= concept[:definition] %></p>
  </div>
</details></span>
```

Notes:

- The `<span class="ck-concept">` wrapper keeps the term and its ⓘ together and
  is the positioning context for the absolute popover panel.
- ERB tag placement avoids inserting whitespace between the term and the ⓘ.
- `heroicon_tag` is the engine's icon helper (from `heroicons-rails`); the
  signature `heroicon_tag "name", variant: :outline, size: N, class:, "aria-hidden":`
  matches existing engine view usage.

### 3. Styling — engine `app/assets/stylesheets/completion_kit/application.css`

New `.ck-concept` block, placed near the existing `.ck-flyout` rules and reusing
the same visual tokens.

- `.ck-concept` — `position: relative; display: inline;` (or `inline-block` on
  the wrapper) so the popover anchors to the term.
- `.ck-concept__toggle` — the `<summary>`: inline, removes the default
  disclosure marker (`::-webkit-details-marker`, `::marker`), small ⓘ icon in
  `--ck-dim`, hover/`[open]` → `--ck-text`, a small left margin, `cursor: pointer`.
- `.ck-concept__icon` — sized ~`0.9em`, `vertical-align` tuned to sit on the
  text baseline.
- `.ck-concept__pop` — `position: absolute`, opens below the term, `z-index`
  above cards, width ~`18rem`, `max-width` clamped to the viewport, background
  `--ck-bg-strong`, `1px` `--ck-line-strong` border, `--ck-radius`, soft shadow
  consistent with `.ck-flyout__panel`.
- `.ck-concept__name` — mono, uppercase-ish kicker styling, `--ck-text`.
- `.ck-concept__body` — `--ck-muted`, `0.8rem`, normal weight.
- Mobile (`max-width: 640px`) — pin the panel to a non-clipping position
  (fixed bottom sheet, mirroring the `.ck-flyout` mobile treatment) so it can
  never spill off-screen.

### 4. View edits — `standalone/app/views/home/index.html.erb`

In the `<% else %>` onboarding branch:

- Step 1 copy: wrap "provider" with the partial
  (`render "concept", term: "provider", key: :provider_credential`).
- Step 2 copy: wrap "prompt".
- Step 3 copy: apply the reword, and wrap "Run", "dataset", "responses",
  "metrics".

Each concept is wrapped once, at the listed occurrence. Other occurrences of the
same word (e.g. "prompt" reappearing in Step 3) are left as plain text to avoid
repeated icons.

## Interaction

- Click (or keyboard-activate) the ⓘ → the `<details>` opens, showing the
  popover. Click again, or click another ⓘ's summary, to close. Native
  `<details>` behaviour; no JavaScript.
- Multiple tips can be open at once; this is acceptable and matches native
  `<details>` semantics. No coordination logic.

## Out of scope

- A dedicated "Concepts" reference card.
- Tips for Metric Group and Tag.
- Tips anywhere outside the onboarding empty state (dashboard, forms, index
  pages).
- Auto-closing other open tips when one opens.

## Testing

All changes are standalone-app views/helpers plus engine CSS — none touch engine
library code, so the engine's RSpec 100%-coverage gate is unaffected.
Verification is a visual check of the onboarding empty state (fresh database, no
provider/prompt/run): each ⓘ renders inline, opens its popover on click, the
popover is readable and on-brand, and it does not clip at a 390px viewport.
