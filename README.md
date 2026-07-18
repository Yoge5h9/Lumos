# Lumos

**A calm, ambient macOS glow that shows — at a glance, without opening anything — how much
of your Claude 5-hour usage window is left, and when it resets.**

Lumos lives as a colored glow around your MacBook notch and/or a colored dot in the menu
bar. Green means plenty of runway; it warms toward amber and red as you approach the limit
or start burning fast. Hover for the exact numbers. It also has a small, opt-in "aware-of-you"
side: a gentle context-rot warning, a best-time-to-start-your-window insight, and rotating
Claude Code pro-tips — all under a strict calm contract (dismissible, capped, per-type mute,
master off).

> **Status:** pre-release / in active development. The design is being finalized in the
> browser (`design/`); the macOS app is being built. Working name `claude-notch` →
> public name **Lumos**.

## Principles

- **Glanceable over detailed** — one color by default; numbers on hover.
- **Calm** — never nags or pops uninvited; ambient by default, always dismissible.
- **Local & private** — no accounts, no API keys, no network, no telemetry.
- **Effortless** — near-zero setup, works on all Macs (auto-detects the notch), reversible.

## Design showcases

Before anything goes to Swift, every look is prototyped and felt in the browser. Open the
launcher and flip between them:

```
open design/index.html
```

- `design/showcase.html` — the glance: Halo / Bloom / Readout / Bleed, states, and the
  menu-bar dropdown mock.
- `design/notifications.html` — the Context / Timing / Tip notification pills.
- `design/non-notch.html` — how Lumos renders on Macs without a notch.

## How it works (mental model)

Claude Code (≥2.1.x, Pro/Max) pipes a JSON payload — including `rate_limits.five_hour`,
`seven_day`, and `context_window` — to your **status line** on each refresh. Lumos's setup
wraps that status line *non-destructively* to tee the fields into a small local cache; the
app reads the cache and renders the glow. No network calls, ever.

## Install (planned)

Distribution is a **Homebrew build-from-source tap** — it compiles locally, so there's no
Gatekeeper prompt and no Apple Developer account needed:

```
brew install <you>/lumos/lumos
lumos setup
```

Details, update mechanics, size, and trade-offs are in [`DISTRIBUTION.md`](./DISTRIBUTION.md).

## Repo layout

| Path | What |
|---|---|
| [`PRODUCT.md`](./PRODUCT.md) | Product brief — vision, features, positioning, naming. |
| [`DESIGN.md`](./DESIGN.md) | Visual lexicon, states, colors, animation specs. |
| [`PLAN.md`](./PLAN.md) | The v1.0 build plan (features, phases, verification). |
| [`DECISIONS.md`](./DECISIONS.md) | Running log of locked product/engineering decisions. |
| [`DISTRIBUTION.md`](./DISTRIBUTION.md) | What it is, install, updates, size, concerns. |
| [`CLAUDE.md`](./CLAUDE.md) | The contract for anyone (human or AI) working in this repo. |
| `design/` | Self-contained HTML design prototypes. |
| `Sources/`, `Tests/`, `Package.swift` | The Swift app + data layer. |

## Contributing / development

Read [`CLAUDE.md`](./CLAUDE.md) first — it's the non-negotiable contract, including the
**development-safety rule**: building Lumos must never touch your real `~/.claude` config;
all setup logic is developed and tested against a temporary sandbox. Visual changes are
agreed in an HTML preview before they go to Swift.

## License

MIT — see [`LICENSE`](./LICENSE).
