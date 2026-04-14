# CompletionKit v0.1.0 launch — design

## Context

CompletionKit is feature-complete on `main` at version `0.1.0` (still tagged `[Unreleased]` in the changelog). The code is in good shape: 425 specs at 100% line + branch coverage, encrypted provider credentials, MCP server with 36 tools, REST API, AI-assisted prompt suggestion workflow, Turbo-driven progress UI, fresh README with logo and screenshots, current dependency tree (no open Dependabot advisories). It has never been published to RubyGems and has no public landing page.

The launch is **gem push + landing page + launch content**. No hosted demo (the standalone instance running on Render+Supabase is private and stays that way).

## Goals

1. Ship `completion-kit 0.1.0` to RubyGems so `gem install completion-kit` works.
2. Publish a static landing page at `https://completionkit.com`.
3. Have launch content drafted and ready (HN, X thread, Ruby Weekly, r/rails, blog post).
4. Add OpenRouter as a fourth provider before the launch ships, so the marketing claim "100+ models" is accurate not aspirational.

## Non-goals

- Public hosted demo (avoids API-spend abuse and launch-day fire-fighting).
- Any JS toolchain for the site (Astro/Next/Vite/etc.).
- A second repo for marketing.
- Pricing, billing, or any "pro" tier.
- Paid ads, podcast outreach, conference CFPs.
- Solid Queue migration (separate concern from launch).
- Standalone deploy guidance — that's private ops in `project_render_runbook.md`.
- Curation / "favorites" of OpenRouter models, search/typeahead in dropdowns, or any post-launch UX polish.

## Decisions locked in conversation

| # | Decision |
|---|---|
| 1 | GitHub Actions workflow deploys `site/` to GitHub Pages (not the Pages "branch + folder" mode, which doesn't support `/site`). |
| 2 | CompletionKit-only landing page; Homemade Software gets a footer byline only. |
| 3 | Add OpenRouter as a fourth provider before launch. |
| 4 | Relabel the existing `"llama"` provider in the UI to "Llama / Ollama / Custom endpoint". The provider string in the DB stays `"llama"` for backwards compatibility. |
| 5 | Tagline: "Prompt testing across OpenAI, Anthropic, Ollama, and any model OpenRouter supports." |
| 6 | OpenRouter dropdown UX: show all discovered models with `<optgroup>` grouping by upstream namespace. No curation, no manual-add flow. |
| 7 | Skip per-model probing for OpenRouter; trust the API's metadata for `supports_generation`. |
| 8 | Refactor `ProviderCredential` counter methods to use `Model` table lookup instead of regex pattern matching. Filter prompt count to `current: true` versions. |

## Positioning

**Audience**: developers building AI features who want to know whether their prompts actually work, and who don't want to commit to a single model vendor.

**Differentiators** (real, in priority order):

1. **Multi-model, including local.** OpenAI, Anthropic, Ollama (or any OpenAI-compatible local endpoint), and 100+ models via OpenRouter — all in one tool. Hosted SaaS competitors can't reach `localhost`. Most provider-native tools (OpenAI Evals, Anthropic Workbench) only test their own provider's models.
2. **Input-balance experimentation, not model bake-offs.** A `Run` captures every input that shapes the result (prompt, dataset, model, temperature, judge, rubric, metrics). Iterate any of them and watch what moves the score. Other tools mostly only let you swap the prompt or the model.
3. **AI-suggested improvements grounded in actual run data.** Anthropic's "prompt improver" is generic. CompletionKit's suggestion reads the LLM-judge feedback from your scored runs and proposes a fix anchored in real failures. Diff view, then apply as a new published version.
4. **Prompt versioning + API publishing + MCP.** Versioned prompts shipped via REST or MCP. The combination means an external system (CI, agent, script) can publish a new prompt version without humans in the loop.

**Tagline + subhead** (hero block on landing page):

> # Prompt testing across OpenAI, Anthropic, Ollama, and any model OpenRouter supports.
>
> #### Score every output against your own rubric. Tune any input — prompt, model, temperature, dataset — and watch what actually moves the numbers.

**Comparable map** (the table that goes on the landing page, drawn from the conversation research):

| | OpenAI Evals | Anthropic Workbench | Braintrust | Langfuse | Promptfoo | **CompletionKit** |
|---|---|---|---|---|---|---|
| Multi-provider | ✗ | ✗ | ✓ | ✓ | ✓ | ✓ |
| Local models (Ollama) | ✗ | ✗ | ✗ | ✓ | ✓ | ✓ |
| Custom rubrics | partial | partial | ✓ | ✓ | ✓ | ✓ |
| AI-suggested improvements (data-driven) | ✗ | partial (generic) | ✗ | ✗ | ✗ | ✓ |
| Versioned prompts via API | ✗ | ✗ | ✓ | ✓ | ✗ | ✓ |
| MCP server | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Free + OSS | partial | partial | ✗ | ✓ | ✓ | ✓ |

---

## Work units

The launch is broken into four sequential work units. Each is a focused commit (or small commit cluster) with its own verification.

### Work unit 1 — OpenRouter provider + counter refactor

**Goal**: add OpenRouter as a fourth provider so the launch tagline is honest. Fix the brittle regex-based counter keying that breaks for namespaced model IDs.

**Files to change**

`app/models/completion_kit/provider_credential.rb`
- Add `"openrouter"` to `PROVIDERS`.
- Update `PROVIDER_LABELS`: `"llama" => "Llama / Ollama / Custom endpoint"`, `"openrouter" => "OpenRouter"`.
- Replace `prompt_count`, `judge_count`, `last_used_at` with `Model`-table-lookup versions:
  ```ruby
  def prompt_count
    model_ids = Model.where(provider: provider).pluck(:model_id)
    Prompt.where(llm_model: model_ids, current: true).count
  end

  def judge_count
    model_ids = Model.where(provider: provider).pluck(:model_id)
    Run.where(judge_model: model_ids).count
  end

  def last_used_at
    model_ids = Model.where(provider: provider).pluck(:model_id)
    Run.where("prompt_id IN (?) OR judge_model IN (?)",
              Prompt.where(llm_model: model_ids).select(:id), model_ids)
       .where.not(status: "pending")
       .maximum(:created_at)
  end
  ```
- Delete `model_pattern` method entirely.

`app/services/completion_kit/llm_client.rb`
- Add an OpenRouter case in `LlmClient.for_provider` that returns an OpenAI-compatible client pointed at `https://openrouter.ai/api/v1`. Required headers: `Authorization: Bearer <api_key>`, `HTTP-Referer: https://completionkit.com`, `X-Title: CompletionKit`.
- Implementation can subclass or compose the existing OpenAI client class — whichever the codebase pattern prefers. No duplication.

`app/services/completion_kit/model_discovery_service.rb`
- Add `fetch_openrouter_models` that GETs `https://openrouter.ai/api/v1/models` (with the same `fetch_connection` timeout helper added in commit `02dd0a5`), filters the response to models where `context_length >= 8192` and `deprecated` is not true, returns `[{ id:, display_name: }, …]`.
- Add an `"openrouter"` case in `fetch_models`.
- Modify `refresh!` so OpenRouter skips `probe_new_models` entirely. Insert OpenRouter models with `supports_generation: true` and `supports_judging: nil` directly during `reconcile`. Failure on first actual use will mark them failed at runtime — acceptable for a v1 trade-off.

`app/helpers/completion_kit/application_helper.rb` (or wherever `ck_model_options_html` lives)
- Update the helper to render `<optgroup>` blocks instead of a flat `<option>` list.
- Grouping rule:
  - For direct providers (`openai`, `anthropic`, `llama`): one `<optgroup label="OpenAI" />` per provider.
  - For `openrouter`: parse the prefix from each model_id (everything before the first `/`) and create one `<optgroup label="OpenRouter — openai" />` per upstream namespace. Sort optgroups alphabetically by upstream within the OpenRouter section.
  - Final order: direct providers first (alphabetical), then OpenRouter optgroups.

`app/views/completion_kit/provider_credentials/_form.html.erb`
- Verify the provider dropdown reads from `PROVIDERS` so OpenRouter shows up automatically.

`spec/services/completion_kit/model_discovery_service_spec.rb`
- New describe block `#refresh! for openrouter` covering: discovers and inserts models with `supports_generation: true`, filters by `context_length`, drops deprecated entries, does NOT call any probe methods, handles namespaced model IDs without crashing reconcile.

`spec/models/completion_kit/provider_credential_spec.rb`
- Update existing counter tests for the new `Model`-table-lookup behavior. Verify `current: true` filter on prompt_count.
- Add tests for openrouter provider.

`spec/factories/provider_credentials.rb`
- Add `:openrouter` trait.

`spec/factories/models.rb`
- Verify there's a model factory and add openrouter trait if needed.

**Verification**
- All 425+ specs pass, line and branch coverage stay at 100%.
- A new OpenRouter credential created via the UI populates `completion_kit_models` with ~150–200 rows in <30 seconds and never makes a probe API call.
- Dropdown HTML on prompt and run forms shows optgroups grouped by upstream provider (verify by curl-ing the page or hitting it in the browser).
- Existing OpenAI and Anthropic credentials still work unchanged.
- `prompt_count` on existing credentials returns the same numbers as before for current versions only (regression check against the old pattern method, with the understanding that draft/old-version prompts are now correctly excluded).

### Work unit 2 — Cut v0.1.0 and publish to RubyGems

**Prerequisites**
- `damien@homemade.software` account on rubygems.org with 2FA enabled.
- `gem signin` already run on this machine (or run as part of the steps).

**Steps**
1. Verify `lib/completion_kit/version.rb` shows `"0.1.0"`. (Already correct — no edit expected.)
2. Update `CHANGELOG.md`:
   - Rename `## [Unreleased]` heading to `## [0.1.0] - 2026-04-14`.
   - Add a new empty `## [Unreleased]` section above it.
   - Append a bullet under `## [0.1.0]` for the OpenRouter provider + counter refactor that landed in Work Unit 1.
   - Add `[0.1.0]: https://github.com/homemade-software-inc/completion-kit/releases/tag/v0.1.0` to the bottom links section.
3. Commit as `chore: release 0.1.0`.
4. `git tag v0.1.0` and `git push origin main --tags`.
5. `gem build completion-kit.gemspec` — produces `completion-kit-0.1.0.gem`.
6. `gem push completion-kit-0.1.0.gem`.
7. **Smoke test in a throwaway Rails app** before announcing anywhere:
   ```bash
   cd /tmp && rails new ck-smoke --minimal --skip-test --skip-system-test
   cd ck-smoke
   bundle add completion-kit
   bin/rails generate completion_kit:install
   bin/rails db:migrate
   bin/rails s
   # confirm /completion_kit loads, prompts index works
   ```
   This catches `files` glob errors in the gemspec that the local development install doesn't surface (because the local install uses `path:`, not the published gem).
8. Create a GitHub release from the `v0.1.0` tag with the changelog 0.1.0 section as the body.
9. Verify `https://rubygems.org/gems/completion-kit` renders summary, README, and dependency list.

**Verification**
- `gem search completion-kit` returns `0.1.0`.
- Throwaway smoke-test app boots and serves `/completion_kit`.
- GitHub release page exists and is linked from rubygems.org.

### Work unit 3 — Landing page at `completionkit.com`

**Goal**: a single static HTML page that converts visitors. Plain HTML+CSS, no JavaScript, no build step, deployed via GitHub Actions to GitHub Pages with the custom `completionkit.com` domain.

**File structure**

```
site/
├── index.html
├── style.css
├── CNAME              # contains "completionkit.com"
├── favicon.png        # copy of docs/logo.png
├── og.png             # 1200×630 social card
├── robots.txt         # allow all
├── sitemap.xml        # single URL
└── img/
    ├── logo.png       # copy of docs/logo.png
    ├── prompts.png    # copy of docs/screenshots/prompts.png
    ├── prompt-detail.png
    ├── test-run.png
    └── demo.gif       # captured in Work Unit 4

.github/workflows/pages.yml   # GH Actions deploy workflow
```

**`site/index.html` sections**

1. **`<head>`** — title, meta description, OG card meta, Twitter card meta, favicon, link to style.css. Title: `"CompletionKit — Prompt regression testing for every model you use"`. Meta description: 150-char paraphrase of the tagline.
2. **Nav** — logo (img + "CompletionKit" wordmark) on the left; "Docs" (jumps to GitHub README), "GitHub", "RubyGems" on the right.
3. **Hero** — H1 (the tagline), H2 sub (the input-balance subhead), two CTAs side-by-side: a click-to-copy `gem install completion-kit` block and a "View on GitHub" button. To the right or below, the `prompts.png` screenshot.
4. **Problem** — 3 short sentences. "You change a prompt. You think it works better. You ship it. Two weeks later, an edge case you forgot to test surfaces in production. CompletionKit catches that before deploy."
5. **How it works** — 3-step diagram with mini code snippets:
   1. Mount the engine (or run standalone) — `gem "completion-kit"` snippet.
   2. Bring a dataset and a prompt — CSV upload UI screenshot or curl example.
   3. Run, score, iterate — screenshot of `test-run.png`.
6. **Demo** — inline `demo.gif` (≤4 MB) showing the live happy-path with Turbo Streams progress.
7. **Comparison table** — the table from the Positioning section above, rendered as HTML.
8. **Feature grid** — 6 cards, 2 columns × 3 rows on desktop, 1 column on mobile:
   - Multi-model: OpenAI, Anthropic, Ollama, OpenRouter
   - Custom metrics with rubric bands
   - LLM-as-judge scoring
   - Prompt versioning + AI-suggested improvements
   - REST API + MCP server (36 tools)
   - 100% test coverage, MIT license
9. **Install** — full setup snippet from the README (`gem`, `generate`, `db:migrate`). Click-to-copy on each block.
10. **FAQ** — 4 short questions:
    - Which providers does it support? (OpenAI, Anthropic, Ollama / any OpenAI-compatible endpoint, and 100+ models via OpenRouter.)
    - Does it work outside Rails? (CompletionKit is a Rails engine that you can also run as a standalone Rails app — you don't need to be a Rails developer to deploy it.)
    - Is it free? (Yes, MIT-licensed, free forever.)
    - Who made it? (Homemade Software.)
11. **Footer** — copyright, "Made by Homemade Software" link to homemade.software, MIT license link, GitHub link, RubyGems link.

**Styling** (`site/style.css`)
- System font stack: `system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`.
- Dark text on light background. Single accent color: `#06B6D4` (cyan from the logo).
- Mobile-first single column, `max-width: 720px` clamp on the main content, generous line-height, large headings.
- No CSS framework. Hand-written, no preprocessor.
- Code blocks use a system mono font with `#0f172a` background and light text — match the README's code style.
- No animations, no transitions beyond a subtle hover state on links and buttons.

**OG card creation** (`site/og.png`)
- Build a tiny HTML+CSS template at `scripts/og-template.html` with the tagline + logo + a generic background gradient.
- Render at 1200×630 via Playwright (`page.setViewportSize`, `page.screenshot`).
- Save the rendered PNG to `site/og.png` and commit it.
- Document the script in a comment so it's reproducible.

**Favicon**
- Use `docs/logo.png` directly. Modern browsers accept PNG favicons. No SVG conversion needed.

**`.github/workflows/pages.yml`** — GitHub Actions deploy
```yaml
name: Deploy site to Pages
on:
  push:
    branches: [main]
    paths: ["site/**", ".github/workflows/pages.yml"]
permissions:
  contents: read
  pages: write
  id-token: write
concurrency:
  group: pages
  cancel-in-progress: false
jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./site
      - id: deployment
        uses: actions/deploy-pages@v4
```

**DNS configuration** (manual step the user does at the registrar)
- Four A records pointing to GitHub Pages IPs:
  - `185.199.108.153`
  - `185.199.109.153`
  - `185.199.110.153`
  - `185.199.111.153`
- One CNAME: `www → homemade-software-inc.github.io`
- After the workflow's first successful deploy, enable "Enforce HTTPS" in the repo's Pages settings (cert provisioning takes 5–30 minutes after DNS propagates).

**Verification**
- `https://completionkit.com` returns 200 and serves `index.html`.
- `https://www.completionkit.com` redirects to apex.
- HTTPS cert is valid (not the default `*.github.io` cert).
- Lighthouse scores ≥95 across Performance, Accessibility, Best Practices, SEO.
- OG card renders correctly in the Twitter Card Validator and the Facebook Sharing Debugger.
- Click-to-copy snippets work in macOS Safari, Chrome, and iOS Safari.
- All three screenshots load at retina resolution.
- The demo gif plays inline on mobile.
- All external links open in a new tab and resolve.
- The site does NOT link to the private Render instance anywhere; `robots.txt` allows all but does not advertise the Render URL.

### Work unit 4 — Launch content + demo gif capture

**Goal**: have every piece of launch content drafted, proofread, and committed before launch day. The T-0 sequence then becomes "publish, post, post, post" with no copywriting under pressure.

**Files** (all in `site/launch/`, not deployed by the Pages workflow)

**`blog-post.md`** — ~800 words, structured as:
- Hook: a specific moment ("I shipped a prompt change last quarter that made the output 12% worse on a metric I wasn't tracking…")
- The problem: manual prompt testing leaves regressions invisible
- What CompletionKit does: short walkthrough with the demo gif inline
- How it's different: 3 short paragraphs comparing to OpenAI Evals + Anthropic Workbench + Langfuse, each ending in "…and CompletionKit does X"
- Install snippet + CTA + link to landing page
- Hosted on `homemade.software/blog/` if it exists, otherwise on `dev.to/@damienbastin` cross-posted, with `completionkit.com` set as the canonical URL.

**`hn.md`** — title + first comment + URL submission
- Title: `Show HN: CompletionKit – Prompt testing across OpenAI, Anthropic, and Ollama`
- URL: `https://completionkit.com`
- First comment (~150 words): author intro, why I built it, link to blog post, invitation for feedback. Mentions the demo gif fallback so HN readers aren't expecting a hosted demo.

**`x-thread.md`** — 6 tweets
1. Hook + tagline + screenshot
2. Problem statement
3. How CompletionKit answers it (demo gif)
4. Code snippet (install + minimal usage)
5. The MCP / multi-provider angle
6. CTA + landing page link
- Pinned on `@damienbastin` on launch day.

**`ruby-weekly.md`** — 1-paragraph pitch
- Recipient: submission form at https://rubyweekly.com (preferred) or `peter@cooperpress.com`
- Body: gem name, gem URL, one screenshot, one-sentence description, link to landing page
- Sent T-7 days before launch (Ruby Weekly publishes Thursdays)

**`reddit.md`** — r/rails post
- Title: `CompletionKit: a Rails-native prompt testing platform with an LLM-as-judge, MCP server, and multi-model support (MIT, just shipped 0.1.0)`
- Body: lifts the blog post intro, links to landing page and GitHub
- Posted afternoon of launch day, after HN has stabilized

**Demo gif capture** (`site/img/demo.gif`)

The demo gif is the single most important marketing asset since there's no hosted demo. Capture procedure:

1. On the local dev machine, reset and reseed the standalone DB:
   ```bash
   cd standalone
   rm db/development.sqlite3
   bin/rails db:create db:migrate db:seed
   ```
2. Set `OPENAI_API_KEY` in `.env` to a real key with a small budget cap.
3. Boot the server: `bin/rails s -p 3000`.
4. Open a screen recorder (Loom for the upload + a local recorder for the gif export).
5. Walk through the happy path **once** — opening Prompts index, opening a prompt, creating a new run with the seeded dataset, hitting "Generate", **watching the actual Turbo Streams progress bar advance** as `gpt-4o-mini` runs the 5 inputs (≤10 cents of API spend), then the Judge step runs and scores populate, landing on the scored results view sorted by score.
6. Export the recording as a ≤4 MB GIF for the inline fallback at `site/img/demo.gif`.
7. Upload the same recording to Loom for HN/X embeds and store the URL in the launch content files.

The pre-baked seed run can't show real progress in motion — it's saved with `status: "completed"` and pre-existing reviews. The 10-cent real generate is the only way to capture the live Turbo Streams progress bar, which is the most visually compelling moment in the product.

**Verification**
- Each launch content file proofread; all external links resolve.
- HN title is ≤80 characters and the URL loads.
- X tweets are each ≤280 characters with no broken links.
- Ruby Weekly submission acknowledged (email reply or form confirmation).
- r/rails post is formatted with markdown preview before posting.
- Demo gif is ≤4 MB, plays inline on mobile, shows the actual Turbo Streams progress bar.
- Loom URL is permalinked and embeddable.

---

## Launch day sequence

Order matters — every piece of content must point at things that already exist.

| When | Action |
|---|---|
| **T−7 days** | Submit to Ruby Weekly via the submission form. |
| **T−2 days** | Verify `completionkit.com` DNS has propagated and HTTPS cert is valid. |
| **T−1 day** | Final end-to-end dry run — `gem install completion-kit` in a throwaway Rails app, walk the happy path, re-record the Loom if anything looks stale. |
| **T−0 morning (PT)** | Publish blog post. Post HN submission (aim for 7–9am PT, Tue/Wed are best). Post the X thread, pin it on `@damienbastin`. |
| **T−0 afternoon** | Post to r/rails once HN has stabilized (avoids same-hour crosspost flagging). |
| **T−0 evening** | Reply to every comment on HN and Reddit. File any bug reports as GitHub issues tagged `from-launch`. |
| **T+1 to T+7** | Triage launch-day issues. Cut `0.1.1` if anything critical surfaces. |

## Risks and monitoring

- **HN front page traffic spike.** GitHub Pages handles this trivially (the cache layer in front of Pages is overprovisioned for static assets). Not a real risk.
- **Bug reports tagged `from-launch`.** Triage daily for the first week.
- **API spend on the private Render instance.** The instance is private and not linked from the landing page, but if anyone discovers the URL via DNS lookup or social media, they could hit it. Confirm before launch that the Render instance has `COMPLETION_KIT_PASSWORD` set so the web UI requires auth, and that the API token is opaque enough to not be guessable.
- **Provider API spend during demo gif capture.** Capped at ~10 cents using `gpt-4o-mini` and a 5-row dataset. Acceptable.
- **Show HN guideline compliance.** "Show HN" requires either a working demo OR a blog post explaining the work. We have the blog post + demo gif + Loom video, which qualifies. The HN title is hedged ("Show HN: …") but we're not posting the URL of the private Render instance.

---

## Out of scope (deferred)

- Curated default subset of OpenRouter models. Ship the full ~150–200 with optgroup grouping; revisit curation post-launch.
- Search / typeahead in the model dropdown. Optgroup is enough for v1.
- Rename the `"llama"` provider string to something like `"openai_compatible"`. Schema-touching change; not worth the migration risk for v0.1.0. UI label fix is enough.
- A "favorite/star a model" feature for personal curation.
- Solid Queue migration (separate concern from launch — the `:async` adapter is the known-acceptable trade-off for single-instance scale).
- A second landing page or microsite for Homemade Software. Footer byline only.
- A blog on `completionkit.com` itself. The launch blog post lives on `homemade.software` or `dev.to`.
- Analytics. The site has no analytics by design — privacy-conscious launch, accept the loss of traffic visibility.

## Open questions

None — all decisions locked in conversation.
