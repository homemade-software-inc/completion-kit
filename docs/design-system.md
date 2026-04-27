# CompletionKit Design System

A briefing for a designer joining the project. Documents what exists today across two surfaces, the conventions that hold them together, and the inconsistencies that a designer should weigh in on.

## 1 — Intent

CompletionKit is a developer tool for testing GenAI prompts. The visual system reads like an instrument panel for engineers who care about precision: dark, monospace-forward, single bright accent. Not a product trying to feel "friendly" or "approachable" — it's trying to feel **rigorous**, **terminal-adjacent**, and **information-dense without being cluttered**.

**The one-line read:** "Linear, but for an LLM eval bench."

What we want to keep:
- Dark mode only (no light theme exists or is planned).
- Monospace as the typographic signature — used aggressively, not just for code.
- A single saturated accent (cyan), used sparingly. Most of the surface is grayscale.
- Soft cyan glow as the default emphasis device, not heavy drop shadows.
- Letter-spaced uppercase mono for any label, badge, or button text.

What we don't want:
- Purple gradients. Glassmorphism for its own sake. Animated gradients. AI-product clichés.
- Multiple competing brights.
- Decorative illustration. Iconography is line, single-weight, semantic only.
- Light mode at the cost of any dark-mode polish.

## 2 — Two surfaces, currently divergent

There are two CSS systems in the repo. They share an aesthetic but the token names and conventions are different. A designer will likely want to reconcile this.

| Surface | Path | Tokens | Audience |
|---|---|---|---|
| App (Rails engine + standalone) | `app/assets/stylesheets/completion_kit/application.css` (~2200 lines) | `--ck-*` prefix, `ck-*` BEM-ish class names | Daily users of the tool |
| Marketing site | `site/style.css` (~340 lines) | unprefixed `--*` tokens | Visitors, prospective users |

The palette is the same hex values; the variable names are not. Same fonts; different scales. Same accent; different button shapes. **Reconciling these into one shared token layer (and possibly a shared CSS file) is a candidate first move.**

Screenshots of the current app are in `docs/screenshots/` (also referenced from the README).

## 3 — Color

All values are the literal hex values used in CSS today.

### Backgrounds (deepest → softest)

| Role | App token | Site token | Hex | Use |
|---|---|---|---|---|
| Page background | `--ck-bg` | `--bg` | `#080b14` | The default canvas. Near-black with a blue undertone. |
| Strong panel | `--ck-bg-strong` | `--bg-surface` | `#0d1117` | Inputs, code blocks (slightly higher than page). |
| Surface | `--ck-surface` | `--bg-raised` | `#111827` | Cards, panels, raised UI. |
| Surface soft | `--ck-surface-soft` | — | `#151d2e` | Tints inside surfaces (rubric rows, badge fills). |
| Surface hover | `--ck-surface-hover` | — | `#1a2332` | Hover state for cards and rows. |

### Lines

| Role | App token | Hex | Use |
|---|---|---|---|
| Default border | `--ck-line` | `#1e293b` | Standard 1px borders. |
| Strong border | `--ck-line-strong` | `#334155` | Inputs, secondary buttons (more prominent edge). |

### Text

| Role | App token | Site token | Hex | Use |
|---|---|---|---|---|
| Body | `--ck-text` | `--fg` | `#e2e8f0` | Primary text on dark surfaces. |
| Muted | `--ck-muted` | `--fg-dim` | `#8b9ab5` (app) / `#94a3b8` (site) | Secondary copy, hints, captions. |
| Dim | `--ck-dim` | `--fg-faint` | `#64748b` | Tertiary metadata, separators in breadcrumbs. |

> Slight divergence: app `--ck-muted` is `#8b9ab5`, site `--fg-dim` is `#94a3b8`. Functionally similar; worth picking one.

### Accent (the only loud color in the system)

| Role | Token | Hex | Use |
|---|---|---|---|
| Accent | `--ck-accent` / `--accent` | `#06b6d4` | Cyan. Brand, primary actions, focus rings, links. |
| Accent hover | `--ck-accent-hover` | `#22d3ee` | Hover on links and links-as-actions. |
| Accent deep | `--accent-deep` (site only) | `#0891b2` | Darker pressed state, primary CTA hover on marketing. |
| Accent soft | `--ck-accent-soft` / `--accent-glow` | `rgba(6, 182, 212, 0.1)` (app) / `rgba(6,182,212,0.08)` (site) | Focus glow, subtle fills, hero gradient. |

The accent is the **only** chromatic color used for emphasis. Treat it as expensive — most surfaces are grayscale; cyan signals "this matters."

### Semantic states

| Role | Token | Hex | Soft variant |
|---|---|---|---|
| Success | `--ck-success` | `#2dd4a8` | `rgba(45, 212, 168, 0.1)` |
| Danger | `--ck-danger` | `#f87171` | `rgba(248, 113, 113, 0.1)` |
| Warning | `--ck-warning` | `#e0a458` | `rgba(224, 164, 88, 0.1)` |
| Info | `--ck-info` | `#06b6d4` (same as accent) | `rgba(6, 182, 212, 0.1)` |

Semantic colors are used in pairs: a saturated value for text/border + a 10% soft variant for fills. Badges and inline status indicators are the primary consumers.

## 4 — Typography

### Faces

```
--ck-mono / --mono   = 'JetBrains Mono', 'SF Mono', 'Fira Code', 'Cascadia Code', monospace
--ck-sans / --sans   = ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif
```

JetBrains Mono is loaded from Google Fonts (weights 400, 500, 700). The sans face is the platform stack — there is no custom display sans. **The personality is carried entirely by JetBrains Mono.** That's a deliberate choice; a designer should decide whether a real display sans (e.g. a geometric or grotesque) belongs in the next iteration or whether keeping the system stack reinforces the "tool, not product" feel.

### Mono is used for

- Brand wordmark
- Page titles (in the app, but **not** on the marketing site — see open questions)
- Buttons (uppercase, letter-spaced 0.04em)
- Labels, badges, chips, breadcrumbs (uppercase, letter-spaced 0.08–0.18em)
- Code blocks and inline code
- Numeric scores (`.ck-score` is mono, 2rem, weight 700, letter-spacing -0.04em)
- Form labels and field hints

### Sans is used for

- Body copy and prose
- Hint text under form fields (inside a mostly-mono UI, sans hints feel humane)
- Marketing site h1/h2 (weight 700–800, tight letter-spacing)
- Lead paragraphs

### Scale — app

| Use | Size | Weight | Letter-spacing |
|---|---|---|---|
| Page title (`.ck-title`) | `clamp(1.8rem, 3.5vw, 2.5rem)` | 700 | -0.02em |
| Section title | `1.35rem` | 700 | -0.02em |
| Card title | `1.15rem` | 700 | -0.02em |
| Score (display number) | `2rem` | 700 | -0.04em |
| Body | `1rem` | 400 | normal |
| Lead | `1.05rem` | 400 | normal |
| Hint / field-hint | `0.8rem` | 400 | normal |
| Button | `0.85rem` | 500 | 0.04em uppercase |
| Label / kicker / breadcrumb | `0.8rem` | 500 | 0.08em uppercase |
| Badge / chip | `0.78rem` | 500 | 0.03em uppercase |

Base font-size is **18px** (set on `<html>`). Line-height is 1.5 (app) / 1.75 (site).

### Scale — marketing site

| Use | Size | Weight |
|---|---|---|
| Hero h1 | `clamp(2.6rem, 6vw, 4rem)` | 800 |
| Section h2 | `2.1rem` | 700 |
| Hero subhead | `1.25rem` | 400 |
| Problem quote (mono) | `1.35rem` | 500 |

## 5 — Spacing & radii

Radii: only two values are used. `--ck-radius: 6px` (default — buttons, inputs, chips), `--ck-radius-lg: 10px` (cards, surfaces). Site uses `8px` for buttons and `12px` for feature cards — small inconsistency.

Spacing follows Tailwind-ish rem multiples but isn't tokenized. Most gaps are `0.35rem`, `0.5rem`, `0.75rem`, `1rem`, `1.5rem`, `2rem`. Considered candidate for tokenization if the designer wants tight control.

Layout maxes:
- App container (`.ck-wrap`) — `1200px`
- Form column (`.ck-form-card`) — `36rem` (~576px)
- Marketing prose — `780px`
- Marketing wide — `1060px`

## 6 — Components

### Cards

`.ck-card` / `.ck-result-card` / `.ck-empty` — surface containers.
- Background: `--ck-surface` (`#111827`)
- Border: 1px `--ck-line` (`#1e293b`)
- Radius: `--ck-radius-lg` (10px)
- Padding: `1.5rem`
- `.ck-empty` variant: dashed border, mono italic-feeling copy, smaller padding. Used for "no records yet" placeholders.

### Buttons

All buttons are mono, uppercase, letter-spaced 0.04em, weight 500. Hover lifts 1px (`translateY(-1px)`).

| Variant | Background | Border | Text | Hover |
|---|---|---|---|---|
| Primary (`--primary`) | `--ck-accent` (cyan) | accent | `#080b14` (page bg) | `--accent-hover` + cyan glow |
| Secondary (`--secondary`) | transparent | `--line-strong` | `--muted` | accent border + accent text |
| Success (`--success`) | transparent | `--line-strong` | `--muted` | accent border + accent text *(currently identical to secondary — likely an oversight)* |
| Danger (`--danger`) | transparent | `--line-strong` | `--muted` | danger soft bg + danger text |
| Warning (`--warning`) | transparent | warning border | `--warning` | warning soft bg |
| Info (`--info`) | transparent | info border | `--info` | info soft bg |
| Ghost (`--ghost`) | transparent | transparent | `--dim` | surface bg + muted text |

> Open question: Success looks identical to Secondary today. Either fix the styling or kill the variant.

### Inputs

`.ck-input` — single rule that powers `<input>`, `<select>`, `<textarea>`.
- Background `--ck-bg` (page color, sits inside surfaces)
- Border 1px `--ck-line-strong`
- Focus: accent border + 3px `--ck-accent-soft` glow ring (the signature focus state)
- Variants: `.ck-input--area` (textarea, min-height 10rem, vertical resize), `.ck-input--code` (mono font for prompt templates)

### Badges and chips

Pill-ish, very small (~0.78rem), uppercase mono, letter-spaced. Status badges have semantic color pairs:

| Badge | Color group | Used for |
|---|---|---|
| `--badge--high` | success | High score (4–5 stars) |
| `--badge--low` | danger | Low score (1–2 stars) |
| `--badge--pending` | dim | Run pending, not started |
| `--badge--running` | info + `ck-pulse` animation | Run in progress (pulses 0.6 → 1 opacity, 2s loop) |

### Breadcrumbs

Mono, 0.8rem, dim. `/` separators inserted via `::before`. Hover changes color to accent.

### Stars

`.ck-star` SVG component — outline-only (`--ck-dim` stroke) when empty, filled cyan when active. Used in rubric definition and in score displays.

### Form layout

`.ck-form-card` — single-column grid, `gap: 1rem`, `max-width: 36rem`, **left-anchored within the content column** (not centered in viewport — this is a deliberate choice; see `tmp/form_alignment_comparison.html` for the comparison).

Sidebar grid: `.ck-grid--sidebar` is `minmax(0, 1.6fr) minmax(16rem, 0.8fr)` — the right column is the established place for related context (version history, linked runs).

## 7 — Motion

Restrained. Five primitives carry the whole system:

1. **Hover lift** — buttons and feature cards rise 1–4px on hover, ~0.2s ease.
2. **Focus glow** — 3px cyan-soft halo around focused inputs.
3. **Status pulse** — `ck-pulse` keyframe (1 → 0.6 → 1 opacity, 2s loop) on running badges.
4. **Reveal-on-scroll** — `.reveal` class on marketing site; `opacity 0 → 1` + `translateY(28px → 0)`, 0.65s ease, triggered by IntersectionObserver.
5. **Hero fadeUp** — 0.7s ease with stagger (`0s, 0.12s, 0.24s, 0.4s`) on hero h1, sub, CTA row, screenshot.

No spring physics. No spinning loaders (we use the pulse). No page transitions. Turbo's progress bar uses the accent color.

## 8 — Texture and atmosphere

What stops the dark UI from feeling flat:

- **Topbar blur** — `rgba(8, 11, 20, 0.85)` + `backdrop-filter: blur(16px) saturate(180%)`. Sticky, semi-transparent.
- **Hero radial gradient** — `radial-gradient(ellipse 80% 60% at 50% 40%, rgba(6,182,212,0.06) 0%, transparent 70%)`. Adds atmospheric cyan haze behind the marketing hero.
- **SVG noise overlay** — generated inline as a data URI, `opacity: 0.03`, on the marketing hero. Almost imperceptible, breaks up large dark fields.
- **Cyan glow shadows** instead of dark drop shadows: hero screenshot has `0 0 80px rgba(6,182,212,0.08), 0 24px 80px rgba(0,0,0,0.5)`. Primary CTA hover: `0 6px 24px rgba(6,182,212,0.3)`.
- **Border-light accent** — `rgba(255,255,255,0.06)` for very subtle internal dividers.

## 9 — Iconography

Heroicons (via the `heroicons-rails` gem). Outline weight, 16px or 20px, current color (so they pick up parent text color). Used semantically only — refresh, copy, trash, settings, status indicators. No decorative iconography.

## 10 — Logo

`docs/logo.svg` and `docs/logo.png` are the canonical mark. The wordmark in the topbar is text-only (`completion` + cyan `kit`), 1.25rem mono, weight 700. Brand assets (favicon variants, OG image, etc.) are in `tmp/brand/` (gitignored working files) and `site/img/`.

## 11 — Open questions for the designer

Things that are inconsistent or unresolved today, in priority order:

1. **Token unification.** App uses `--ck-*`, site uses `--*`. Same hex values, different names. Worth a single shared token file.
2. **Page title typography.** App page titles are mono and tight; marketing h1 is sans, weight 800. They feel like different brands. Pick a system rule.
3. **Sans face.** Currently the platform stack. Should we adopt a real display sans? Candidates a designer might propose: Söhne, GT America, Geist, or a more characterful grotesque. Or stay system-stack and lean harder on Mono.
4. **Button radius.** App `6px`, site `8px`. Pick one.
5. **Card radius.** App `10px`, site `12px`. Pick one.
6. **Muted gray hex.** App `#8b9ab5`, site `#94a3b8`. Pick one.
7. **Success vs Secondary buttons** are visually identical. Either differentiate or remove.
8. **Density.** The app currently runs at base 18px font-size, which reads a touch large for an information-dense tool. Worth experimenting with 16px and re-tuning the type scale.
9. **No empty/illustration states.** Empty list states use a dashed-border card with a one-line message. Some screens (Runs index when empty) could justify a small illustration moment — though the brand intentionally avoids decorative imagery.
10. **CompletionKit Cloud surface** is yet to be designed. The dashboard for the hosted multi-tenant product (org switcher, billing, usage) doesn't exist yet — it'll need to either extend or deliberately depart from this system.

## Appendix — Where to look in the code

- App tokens & primitives: `app/assets/stylesheets/completion_kit/application.css` (lines 7–33 are tokens; the rest is component CSS in BEM-ish flat list).
- Site tokens & primitives: `site/style.css` (lines 3–22 are tokens).
- Live screens to review: `app/views/completion_kit/prompts/`, `runs/`, `metrics/`, `provider_credentials/`, `datasets/`. Each has `index.html.erb`, `show.html.erb`, `_form.html.erb` partials.
- Screenshots of current state: `docs/screenshots/`.
- The standalone Rails app (mounts the engine, easiest way to run the UI locally): `cd standalone && bin/rails s`.
