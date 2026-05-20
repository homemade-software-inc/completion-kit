# Onboarding Concept Tips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline info popovers to the onboarding empty state so a new user learns the six core CompletionKit concepts in context.

**Architecture:** A reusable ERB partial renders a concept term followed by a native `<details>` info popover. Definitions live in a `CONCEPTS` hash in a standalone-app helper. Styling is added to the engine stylesheet, reusing the existing `--ck-*` tokens and the `<details>`-popover pattern already used by `.ck-flyout`. No JavaScript.

**Tech Stack:** Rails 8.1 standalone host app, ERB, native HTML `<details>`/`<summary>`, the `heroicons-rails` gem (`heroicon_tag` helper), the engine's `completion_kit/application.css`.

**Context for the engineer:**
- The onboarding empty state is the `<% else %>` branch of `standalone/app/views/home/index.html.erb`. It renders three `.ck-card` step cards (Configure a provider / Create a prompt / Run an evaluation), shown until a provider, a prompt, and a run all exist.
- The standalone app has **no automated test framework** (no RSpec, no Capybara). Verification for this feature is visual, plus a regression run of the engine's own RSpec suite to confirm nothing engine-side broke.
- The engine enforces 100% line+branch coverage on its RSpec suite. This feature changes only standalone views/helpers and engine CSS — no engine Ruby — so coverage is unaffected and must stay green.
- A dev server may already be running on port 3000 from earlier work; stop it before the verification steps.
- The full design is in `docs/superpowers/specs/2026-05-20-onboarding-concept-tips-design.md`.

**File structure:**
- `standalone/app/helpers/home_helper.rb` — *new* — the `CONCEPTS` hash (concept key → name + definition). One responsibility: concept copy.
- `standalone/app/views/home/_concept.html.erb` — *new* — renders one term + its `<details>` info popover. One responsibility: the tip component.
- `app/assets/stylesheets/completion_kit/application.css` — *modified* — appends a `.ck-concept` style block. The engine stylesheet is shared and already hosts the comparable `.ck-flyout` popover styles.
- `standalone/app/views/home/index.html.erb` — *modified* — wraps six concept terms in the partial and lightly rewords Step 3.

**Project conventions (do not violate):**
- No code comments anywhere — not in Ruby, ERB, or CSS.
- No em dashes in copy.
- Commit messages: subject line only, short. No attribution/co-author lines.

---

### Task 1: Concept definitions and the tip partial

**Files:**
- Create: `standalone/app/helpers/home_helper.rb`
- Create: `standalone/app/views/home/_concept.html.erb`

- [ ] **Step 1: Create the concept definitions helper**

Create `standalone/app/helpers/home_helper.rb` with exactly this content:

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

- [ ] **Step 2: Create the concept tip partial**

Create `standalone/app/views/home/_concept.html.erb` with exactly this content. The `-%>` on the first line and the adjacency of `<%= term %>` and `<details>` are deliberate, so the icon sits tight against the word with no stray whitespace:

```erb
<% concept = HomeHelper::CONCEPTS.fetch(key) -%>
<span class="ck-concept"><%= term %><details class="ck-concept__tip"><summary class="ck-concept__toggle" aria-label="What is a <%= concept[:name] %>?"><%= heroicon_tag "information-circle", variant: :outline, size: 14, class: "ck-concept__icon", "aria-hidden": "true" %></summary>
<div class="ck-concept__pop" role="tooltip">
<p class="ck-concept__name"><%= concept[:name] %></p>
<p class="ck-concept__body"><%= concept[:definition] %></p>
</div></details></span>
```

The partial takes two locals: `term` (the display word as it reads in the sentence) and `key` (a `CONCEPTS` key symbol).

- [ ] **Step 3: Verify the helper loads and has six concepts**

Run:

```bash
cd standalone && DISABLE_SPRING=1 bin/rails runner "puts HomeHelper::CONCEPTS.size"
```

Expected output: `6`

If it errors, the helper file has a syntax problem — fix it before continuing.

- [ ] **Step 4: Commit**

```bash
git add standalone/app/helpers/home_helper.rb standalone/app/views/home/_concept.html.erb
git commit -m "add concept tip partial and definitions"
```

---

### Task 2: Concept popover styling

**Files:**
- Modify: `app/assets/stylesheets/completion_kit/application.css` (append at end of file)

- [ ] **Step 1: Append the `.ck-concept` style block**

Append exactly this block to the end of `app/assets/stylesheets/completion_kit/application.css`:

```css
.ck-concept {
  position: relative;
  display: inline;
}
.ck-concept__tip {
  display: inline;
}
.ck-concept__toggle {
  display: inline;
  margin-left: 0.15rem;
  color: var(--ck-dim);
  cursor: pointer;
  list-style: none;
}
.ck-concept__toggle::-webkit-details-marker { display: none; }
.ck-concept__toggle::marker { content: ""; }
.ck-concept__toggle:hover { color: var(--ck-accent); }
.ck-concept__tip[open] .ck-concept__toggle { color: var(--ck-accent); }
.ck-concept__icon {
  width: 0.92em;
  height: 0.92em;
  vertical-align: -0.12em;
}
.ck-concept__pop {
  position: absolute;
  top: calc(100% + 0.4rem);
  left: 0;
  z-index: 40;
  width: 19rem;
  max-width: calc(100vw - 1.5rem);
  padding: 0.7rem 0.8rem;
  background: var(--ck-bg-strong);
  border: 1px solid var(--ck-line-strong);
  border-radius: var(--ck-radius);
  box-shadow: 0 16px 34px rgba(0, 0, 0, 0.5);
  white-space: normal;
  cursor: auto;
}
.ck-concept__name {
  margin: 0 0 0.3rem;
  font-family: var(--ck-mono);
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--ck-text);
}
.ck-concept__body {
  margin: 0;
  font-size: 0.8rem;
  line-height: 1.5;
  color: var(--ck-muted);
}
@media (max-width: 640px) {
  .ck-concept__pop {
    position: fixed;
    inset: auto 0.75rem 0.75rem 0.75rem;
    width: auto;
    max-width: none;
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/assets/stylesheets/completion_kit/application.css
git commit -m "style the concept tip popover"
```

---

### Task 3: Wire tips into the onboarding view and verify

**Files:**
- Modify: `standalone/app/views/home/index.html.erb`

- [ ] **Step 1: Wrap the concept term in Step 1**

In `standalone/app/views/home/index.html.erb`, find the Step 1 copy line:

```erb
        <p class="ck-copy">Add your API key for OpenAI, Anthropic, or another supported provider to start generating responses.</p>
```

Replace it with:

```erb
        <p class="ck-copy">Add your API key for OpenAI, Anthropic, or another supported <%= render "concept", term: "provider", key: :provider_credential %> to start generating responses.</p>
```

- [ ] **Step 2: Wrap the concept term in Step 2**

Find the Step 2 copy line:

```erb
        <p class="ck-copy">Write a system prompt and configure which model to test against. Prompts are versioned so you can track changes over time.</p>
```

Replace it with:

```erb
        <p class="ck-copy">Write a system <%= render "concept", term: "prompt", key: :prompt %> and configure which model to test against. Prompts are versioned so you can track changes over time.</p>
```

- [ ] **Step 3: Reword Step 3 and wrap its four concept terms**

Find the Step 3 copy line:

```erb
        <p class="ck-copy">Run your prompt against a dataset and score the responses with a judge model. Compare results across prompt versions.</p>
```

Replace it with (note the reworded clause "against metrics you define"):

```erb
        <p class="ck-copy"><%= render "concept", term: "Run", key: :run %> your prompt against a <%= render "concept", term: "dataset", key: :dataset %> and score the <%= render "concept", term: "responses", key: :response %> against <%= render "concept", term: "metrics", key: :metric %> you define, with a judge model. Compare results across prompt versions.</p>
```

- [ ] **Step 4: Run the engine test suite as a regression guard**

From the repository root:

```bash
bundle exec rspec
```

Expected: `840 examples, 0 failures`, `Line Coverage: 100.0%`, `Branch Coverage: 100.0%`. This feature touches no engine Ruby, so the suite must be unchanged. If the count or coverage differs, something unintended changed — investigate before continuing.

- [ ] **Step 5: Render the onboarding empty state against an empty database**

The onboarding only renders when no provider, prompt, or run exists, so it needs an empty database. The dev database is seeded, so back it up, prepare an empty one, and start the server.

First stop any server already running on port 3000. Then move the dev database aside — including its SQLite `-wal` and `-shm` sidecar files, so the seeded database can be restored cleanly:

```bash
cd standalone
mkdir -p tmp/db-backup
mv db/development.sqlite3* tmp/db-backup/
DISABLE_SPRING=1 bin/rails db:prepare
DISABLE_SPRING=1 bin/rails server
```

- [ ] **Step 6: Visually verify desktop and mobile**

With the server running, open `http://localhost:3000`. The onboarding empty state ("Prompt Testing Lab", three step cards) renders. Confirm:

- Each of the six terms (`provider`, `prompt`, `Run`, `dataset`, `responses`, `metrics`) shows a small information icon tight against the word.
- Clicking an icon opens a popover showing the concept name and definition; clicking again closes it.
- The popover background, border, and shadow match the dark app styling and the text is readable.
- At a 390px-wide viewport the popover pins to the bottom of the screen and never clips off the edge.

Take a screenshot at desktop width and at 390px width for the review.

- [ ] **Step 7: Restore the seeded database**

Stop the server, then discard the empty database and move the seeded one back:

```bash
cd standalone
rm -f db/development.sqlite3*
mv tmp/db-backup/* db/
rmdir tmp/db-backup
```

- [ ] **Step 8: Commit**

```bash
git add standalone/app/views/home/index.html.erb
git commit -m "show concept tips in the onboarding steps"
```

---

## Notes for the executor

- Tasks 1 and 2 are independent. Task 3 depends on both.
- There is intentionally no automated test for this feature: the standalone app has no test harness, and adding one is out of scope. The engine suite run in Task 3 Step 4 is a regression guard, not a test of this feature.
- Do not add tips for Metric Group or Tag, and do not add a dedicated concepts card. Both are explicitly out of scope.
