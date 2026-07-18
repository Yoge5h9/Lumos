# CLAUDE.md — (working name: claude-notch)

Instructions for any AI/engineer working in this repo. Read before making changes.
The full product thinking lives in [`PRODUCT.md`](./PRODUCT.md); this file is the short,
non-negotiable contract.

## What this is

A calm, ambient macOS tool that shows — **at a glance, without opening anything** — how
much of your Claude 5-hour usage window is left and when it resets. It lives as a colored
glow around the MacBook notch and/or a colored dot in the menu bar.

## The core requirement (non-negotiable)

> **It must be intuitive, and effortless to install, set up, and use.**

Every decision is measured against this first. Concretely:

- **Install & setup is the product.** A power user should go from zero to a working glow in
  ~2 commands, with sensible defaults and no config files to hand-edit. If setup needs a
  manual step, we automate it or explain it in one plain sentence.
- **No manual required.** The UI must be self-evident — a first-time user understands the
  glow's meaning and finds the on/off toggle without instructions.
- **Sensible defaults over options.** Ship the right default; make things tunable later, not
  as a prerequisite. Never block first use on a choice.
- **Fails gracefully & legibly.** If data isn't available yet, say so in human words
  ("waiting for Claude Code…"), never a blank or an error code.
- **Reversible & respectful.** Setup backs up anything it touches (e.g. the user's Claude
  status line) and can be cleanly undone. Never clobber existing config.

If a change makes the tool more capable but less obvious or harder to set up, it is the
wrong change until proven otherwise.

## Development safety (non-negotiable)

> **No destructive or obstructing dev or action.** Building Lumos must never break, degrade,
> or get in the way of the developer's own working machine — especially their live Claude
> Code / `~/.claude` setup.

- **Never touch the real `~/.claude` during development.** Read-only inspection is fine; any
  code that writes/wraps `settings.json`, the status line, or the cache is developed and
  tested against a **temporary sandbox copy**, never the live config. Wiring the real setup
  is a deliberate, user-approved step — never a side effect of a build or test.
- **`lumos setup` must be non-destructive & fully reversible** — back up anything it touches
  (timestamped), wrap (never replace) an existing status line, and restore it byte-for-byte
  on `--uninstall`. Idempotent. If it can't back up safely, it stops and says so.
- **No destructive shell/git actions without explicit per-action approval** — no `rm -rf`,
  no overwriting user files outside the repo, no force/`--yes` on anything mutating, no
  clobbering existing config. Prefer the non-destructive equivalent; if a destructive step
  seems needed, stop and ask.
- **The dev process itself stays out of the way** — don't leave the user's machine in a
  worse state than you found it (no stray login items, launch agents, or config edits left
  behind by testing).

## Collaboration & critique

- **Critique the user's points and think *with* them.** When a request has a weaker and a
  stronger path, say so and recommend — don't just implement. Surface tensions (e.g. a
  feature vs. the calm principle) early rather than after building.
- **Showcase UI/UX in HTML before finalizing.** Any visual change (look, color, animation,
  state, notification) is felt in a `design/*.html` preview and agreed before it goes to
  Swift. This is a hard gate, not a nicety.

## Living docs — keep them current (standing expectation)

The docs must never drift from what the code actually does. This is a manual discipline (no
automation), expected of anyone — human or agent — working in the repo:

- **`PROGRESS.md` is the living build log.** After each meaningful chunk of work (a wave lands,
  a phase completes, a decision changes), update it: what's done + verified, what's in flight,
  what's blocked, and what still needs on-hardware/Xcode verification. It is the first file to
  read to know where things stand.
- **Log new locks in `DECISIONS.md`** (newest first) and **update `DESIGN.md`** when the lexicon,
  states, or palette change. If a doc claim is proven wrong, **correct it** — don't leave a
  known-false statement standing.
- **`CLAUDE.md` stays the stable contract** — change it only when a *principle or rule* changes,
  not for routine progress (that goes in `PROGRESS.md`). Keep it short.
- **Verify before claiming done.** Only record something as "done/verified" in a doc after the
  actual check ran (e.g. `swift build` output) — mirror the honesty bar used in code.

## Product principles

1. **Glanceable over detailed** — default state is one color; numbers are on-demand (hover).
2. **Calm** — never nags or pops uninvited. Ambient by default; escalates only when it truly
   matters, and always dismissible.
3. **Local & private** — no accounts, no API keys, no network, no telemetry. Nothing leaves
   the machine.
4. **Invisible until wanted** — no dock icon; a single menu-bar control to toggle/quit.
5. **One job, done beautifully** — resist scope creep into a dashboard/analytics tool.

## How it works (mental model)

- Claude Code ≥2.1.x pipes a JSON payload (incl. `rate_limits.five_hour`, `seven_day`,
  `context_window`) to the **status line** command on stdin every refresh, for Pro/Max plans.
- Setup wires that status line (wrapping any existing one, non-destructively) to tee the
  fields into a small local cache file.
- The app reads the cache and renders the glow + menu-bar dot. No network calls.

## Tech

- Swift + AppKit (menu-bar-less agent, `setActivationPolicy(.accessory)`). macOS 13+.
- Notch geometry via `NSScreen.auxiliaryTopLeftArea/RightArea` + `safeAreaInsets.top`.
- Distribution: **Homebrew build-from-source** tap (compiles locally → no Gatekeeper prompt,
  free, no Apple Developer account). Details in `PRODUCT.md`.

## Design previews (HTML) — preferred workflow

Before implementing any visual change (new look, color, animation, state), **build a
self-contained HTML preview under `design/`** so the change can be *felt* in a browser
first — no Swift build, instant iteration. The preview should:

- Simulate the notch + menu bar on a dark background.
- **Always show multiple scenarios/cases for that page** — every relevant state side by side
  or via toggles (e.g. Calm/Watch/Alert/Idle, "burning fast", near-limit Breathe, reset
  Refill; for the notch surfaces, both notched and non-notch renderings). A preview that
  shows only one state is incomplete.
- Expose **live controls** (sliders, color pickers) so colors, glow, thickness, timing can be
  tuned by feel.
- Be one file, offline, no external assets.

**Visual-quality bar (non-negotiable).** Every HTML preview and every UI/UX surface must look
**professional, elegant, and visually beautiful** — considered typography and spacing,
refined color and glow, smooth purposeful motion, and a coherent design language across all
pages. "Functional but rough" is not acceptable; treat each preview as a portfolio-grade
artifact. Consistent Lumos branding (name, palette, tone) across every page.

**All design HTML is linked from `design/index.html`.** That tabbed launcher is the canonical
entry point — whenever a new `design/*.html` is added, wire it into `index.html` so every
showcase is reachable from one place. `design/showcase.html` is the running playground —
extend it (or add new `design/*.html`) for each idea. Only port to Swift once the look is
agreed in HTML. These can also be published as a shareable Artifact on request.

## Design lexicon (use these names in all discussion)

See `DESIGN.md` for the canonical list. Core terms: **Halo** (the ring), **Bloom** (its glow),
**Readout** (the info pill), **Bleed** (pill extruding from the notch), **LED** (menu-bar dot),
states **Calm / Watch / Alert / Idle**, future **Breathe / Nudge / Prime / Refill**.

## Out of scope (for now)

Dollar-cost tracking / history charts (that's `ccusage`), multi-account, Windows/Linux,
anything requiring login / API keys / network.

## Naming

Working name `claude-notch`. Final public name TBD (must avoid "Claude"/"Anthropic" for
trademark safety). Candidates and rationale in `PRODUCT.md §7`.
