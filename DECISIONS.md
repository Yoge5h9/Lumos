# Lumos — Decisions log

> The running record of **locked** product/engineering decisions, newest section first.
> Each entry: the decision + a one-line rationale. When something changes, add a new dated
> entry rather than silently rewriting history. Companion to [`PRODUCT.md`](./PRODUCT.md)
> (the "why") and [`PLAN.md`](./PLAN.md) (the "how/when").

## 2026-07-18 — v0.1.0 published to Homebrew

- **Icon: "Wand Tip + Bloom" (woody)** — a tapered walnut→mahogany wand casting an amber bloom.
  Shipped as `Resources/AppIcon.icns` (rasterized via `rsvg-convert` from `Resources/AppIcon.svg`) +
  the onboarding top mark (base64 PNG embedded in `OnboardingMark.swift`, so it renders in the dev
  binary *and* the installed `.app`). Chosen over the "Open Halo" runner-up.
- **Released v0.1.0.** `Yoge5h9/Lumos` is public; tagged + GitHub release; the tap
  (`Yoge5h9/homebrew-lumos`) formula carries the real url + `sha256` (`87200eee…3c66`) and
  **`depends_on xcode` was dropped** (CLT-only build validated — users don't need a 15 GB Xcode).
  `brew info yoge5h9/lumos/lumos` → `stable 0.1.0`; brew fetched the tarball + verified the sha256.
  Install: `brew install Yoge5h9/lumos/lumos && lumos setup`.
- **Caveat:** `brew install --build-from-source` was not run to completion locally — Homebrew's
  CLT-version gate rejects this machine's Command Line Tools as too old. This is an *environment* gate,
  not a formula defect (direct `swift build -c release` is green; `assemble-app.sh` yields a valid
  signed `.app`). Complete the end-to-end install test on a machine with current CLT.

## 2026-07-18 — Data-source lock, stale redesign, capturable notch

- **Data source: pure-local, status-line tee ONLY. Cross-surface sync via the network
  rejected.** Research (two agents) + the user's own prior SwiftBar notch tool + Anthropic docs
  all converge: the 5h/7d `rate_limits` window is delivered *only* through the Claude Code
  status-line stdin payload. There is **no clean local source** that also covers Desktop-app /
  claude.ai usage. The one cross-surface option — the undocumented `GET /api/oauth/usage`
  endpoint (Bearer token from `~/.claude/.credentials.json`) — is **rejected as a default**: it
  breaks all three core promises (local / no-network / no-keys), is **flaky** (three open CC
  issues show it 429-ing for hours), and its token only refreshes while CC runs anyway. The
  Claude Desktop local cache (`~/Library/Application Support/Claude/plan-usage-history.json`)
  has `fh`/`sd` percentages but **no reset time and goes stale even while the app runs** — not
  reliable. **Consequence:** Lumos is a *terminal-Claude-Code* tool; the Desktop/web gap is
  handled by the honest Stale/Waiting UI, not a backdoor. A disclosed, off-by-default opt-in
  toggle remains a *possible future*, never v1.
- **Notch overlay is capturable: `sharingType = .readOnly`** (was `.none`). Rationale: users
  must be able to screenshot/record the glow for demos, support, and sharing; `.none` silently
  excluded it from all screen capture and read as "the notch isn't working." Trade-off accepted:
  the glow now appears in screen shares (mild; it's an ambient indicator). The HUD panel keeps
  its own setting.
- **Stale redesign (supersedes the "Idle invisible" polish item above).** On going stale, Lumos
  **keeps the last-known numbers** and renders the state color **desaturated + dimmed** (a muted
  "greyed-out yellow", NOT neutral gray) and **static** — never blanks to "waiting". Constants:
  **staleness threshold 300s (5 min)**, **desaturation 60%**, **dim 45%** (amber `#FFD60A` →
  ~`rgb(188,167,77)`). Distinguished from a *fade* (which keeps full saturation + moves) by being
  desaturated, motionless, and wearing an age label. **"waiting for Claude Code…" is reserved for
  the no-data-ever case only** (never a stale value).
- **Readout pill is compact (`NN% · <relative reset>`, e.g. `65% · 2h 14m`) ≈ notch width.** The
  resting pill drops "used", the absolute IST time, and the weekly figure; full detail (absolute
  reset time, `wk NN%`) moves to the click **HUD**. The stale **age label** (`stale · updated
  Xm ago`) sits as a small, blended sub-label **below** the pill — never inline (inline widened it
  past the notch). Rationale: "glanceable over detailed" + keep the pill at notch width.

## 2026-07-18 — Build + first on-hardware run

- **`lumos setup` now launches the app + enables launch-at-login by default** (`--no-launch`
  opts out; `--uninstall` unregisters the login item + stops the running app). Rationale: the
  core requirement is "zero to a working glow in ~2 commands" (`brew install` → `lumos setup`).
  Login-item uses `SMAppService.mainApp`, which requires a **real `.app` bundle** — it soft-fails
  on the raw dev binary, so login-at-login only truly works once installed via brew/`assemble-app.sh`.
- **No Apple Events / System Events in the shipped app (TCC-free by design).** Launch/stop uses
  `open`/`Process`/`NSWorkspace`/`NSApplication.terminate`; the notch overlay uses mouse monitors
  only (no Accessibility). Verified grep-clean. A TCC "control System Events" prompt seen during
  development came from `osascript` dev/test commands (Claude Code), **not** Lumos.
- **Idle must be visually perceptible.** A dim-gray Halo on a black notch is invisible and reads
  as "broken" — Idle needs a faint-but-visible treatment and/or a clearer LED, per the
  "fails gracefully & legibly" rule. (v1 polish item.)
- **`setup` mid-session caveat:** the wrapped status line only starts firing in a **new** Claude
  Code session, so data doesn't flow until the user starts one. `setup` should say this.
- **Crash fix (engineering):** ARC-owned `NSWindow`/`NSPanel` held in a property MUST set
  `isReleasedWhenClosed = false` — the AppKit default `true` double-frees on close (this caused a
  launch SIGSEGV via the onboarding window).
- **Lightweight runtime (implemented):** event-driven `DispatchSource` cache watch (no fixed
  polling), glow static at rest, pause on display sleep — see the engineering constraint below.
- **First on-hardware run (Mac16,12):** geometry detection, data pipeline (`setup` → cache), GUI
  render, and the crash fix all verified on a real notched Mac. See `PROGRESS.md`.

## 2026-07-18 — First-release planning session

### Product & naming
- **Public name: Lumos.** On-brand for the glow (the Halo), short, brew-friendly. Working
  folder stays `claude-notch` for now — **rename deferred** (would break in-flight paths /
  session cwd; do it at a quiet break). Repo/command will be lowercase `lumos`.
- **License: MIT.** Public OSS, permissive.

### Scope (v1.0)
- **v1.0 = ambient glance + all three notification types** (Context / Timing / Tip). The
  notification "brain" ships in the first release, not as a fast-follow.
- **Default surfaces ON: Notch Halo + LED both.** Full ambient experience on first run;
  either is toggleable from the menu.

### Notifications — the "calm contract"
- **Three types, each independently controllable:** Context (context-rot warning),
  Timing (window-timing insight), Tip (rotating pro-tip).
- **Per-type daily cap (~1/day).** Context may re-fire for a genuinely *new* session that
  crosses the threshold (it's the one time-sensitive type); de-duped per session so it
  never nags twice for the same session.
- **Every notification is dismissible**, with per-type mute, **"don't show again" per
  specific notification**, **quiet hours**, and a **master off** — all from the menu-bar
  icon. Rationale: keeps the founding "calm, never pops uninvited" principle intact while
  still being aware of the user.
- **Coaching style: gentle push, capped**, with a "seen-it" memory so tips never repeat;
  the tip list is updatable so users learn features effortlessly over time.
- **Notification accent colors are per-type** (Context amber, Timing cyan `#64d2ff`, Tip
  purple `#bf5af2`) — deliberately *separate* from the Calm/Watch/Alert/Idle **state**
  palette, so a pill's color signals its *type*, not usage state.

### Non-notch Macs (finalized)
- **Auto-detect notch geometry**; notched Macs always get the real Halo + Bloom.
- **Non-notch default: Menu-bar LED only** — universal, calmest, never looks wrong.
- **Optional secondary: a thin top-center glow bar** — a slim (~200×4px) rounded glow line
  with soft bloom; a subtle *hint*, explicitly **not** a chunky shape or fake notch.
- **Rejected:** full-width top-edge glow (competes with bright wallpapers) and a floating
  ambient percentage pill (too much persistent chrome).

### Data & architecture
- **Cache: `~/.claude/lumos/cache.json`**, keyed by `session_id`; staleness threshold 90s;
  prune sessions older than 14 days. Lumos-owned — does not clobber existing files.
- **Fields tee'd from the status line:** `rate_limits.five_hour`/`seven_day`
  (`used_percentage`, `resets_at` epoch-seconds), `context_window.used_percentage` +
  `context_window_size`, `model`, `session_id`.
- **Multi-session context watch:** the context warning fires on the **max context % across
  non-stale sessions**, so it catches whichever live session is filling up.
- **Timing intelligence from `~/.claude/history.jsonl`** (epoch-ms, read-only) → local-hour
  histogram; "insufficient data" below ~20 prompts / 3-day span (cold-start); prime time =
  ~1h before the earliest peak hour.
- **Idle handling:** the status line goes quiet when a session is idle / Claude Code is
  closed → treat cache mtime as staleness, show "waiting for Claude Code…", and always
  trust the absolute `resets_at` epoch (valid even when stale).

### Setup, distribution & updates
- **Setup wraps the status line non-destructively:** back up `settings.json` *before* any
  change, **abort and change nothing if the backup can't be made**, idempotent, and
  `--uninstall` restores byte-for-byte (leaving the timestamped backup as an audit trail).
- **Distribution: Homebrew build-from-source tap, ad-hoc signed** (no Apple Developer
  account) → locally compiled → no Gatekeeper prompt. **Verified:** `swift build -c release`
  is green on a **Command-Line-Tools-only** machine (no full Xcode) — confirms the light
  install claim. Build via **SPM + hand-assembled `.app`** (avoids the multi-GB Xcode dep).
- **Updates: auto-detect + one-tap `brew upgrade`** (opt-in daily GitHub version check).
  Not Sparkle (would re-introduce quarantine/Gatekeeper). Launch-at-login via `brew
  services` + in-app `SMAppService` toggle.

### Process & engineering
- **Development safety (non-negotiable):** no destructive/obstructing dev; never touch the
  real `~/.claude` during development — all setup/ingest logic is tested against a temp
  sandbox only.
- **HTML-first:** every UI/UX change is prototyped in `design/*.html` (all reachable from
  `design/index.html`, each showing multiple scenarios) and agreed before it goes to Swift.
- **Visual-quality bar:** every surface must look professional, elegant, and beautiful, with
  a coherent design language across pages.
- **Tests are written with Swift Testing, but the suite needs Xcode to run.** On a
  Command-Line-Tools-only machine *neither* Swift Testing (`Testing` / `_Testing_Foundation`)
  *nor* XCTest resolves — both ship inside `Xcode.app` on macOS — so `swift test` can't
  execute here (verified 2026-07-18: `no such module 'Testing'`). End users are unaffected
  (they only `swift build`, which is green on CLT). **Decision (2026-07-18): stay CLT-only
  for now** — verify logic with a temporary `swiftc` harness (compile the sources + an
  assertion `main`, run, discard). Running the full Swift Testing suite is deferred until
  Xcode is installed (dev-only, ~15 GB base without simulators).
- **Lightweight / zero idle overhead (engineering constraint, 2026-07-18).** Lumos is an
  always-present ambient agent, so it must sip resources: prefer **event-driven** cache reads
  (watch the cache file via FSEvents / `DispatchSource`) over fixed-interval polling; the glow
  renders as a **static CALayer at rest** and animates ONLY on state change or hover (no
  per-frame redraw when idle); pause rendering/timers when the display sleeps; keep the binary
  small (AppKit + Foundation only, no heavy deps). "Calm" includes calm on the CPU.

## Locked — interactions (signed off in `design/interactions.html`, 2026-07-18)

- **Adaptive glow brightness — "dim-at-rest, bright-on-attention."** The Halo/Bloom sits at a
  low, easy-on-the-eyes DIM level by default; blooms to full brightness on hover/activity,
  holds briefly, then eases back to dim. **Alert keeps a higher dim floor** so a near-limit
  glow never fully fades. Rationale: an always-bright ambient glow is distracting — calm means
  quiet-by-default, loud only when it earns attention. **Starting values from the agreed demo:**
  dim floor ~30%, peak 100%, bright-hold ~1 min, fade ~1.4s, Alert floor ≥42% — carry these to
  Swift as tunable defaults.
- **Menu-bar LED: hover = info, click = control.** Hovering the LED shows a custom numbers HUD
  (`% used · resets · wk %`) instantly and calmly; clicking opens the actionable menu. Mirrors
  the notch Readout hover model; keeps click→menu for macOS convention + accessibility.

## Resolved — follow-up decisions (2026-07-18)

- **Glow tracks the 5-hour window ONLY.** The color/state model is driven by the 5h window;
  the 7-day weekly figure appears in the dropdown/Readout but never drives the glow color.
- **Context warning threshold = 40%.** Fires once when a live session crosses 40% context.
- **Notifications are pill-only.** Context / Timing / Tip all render as the custom notch (or
  fallback) pill — no macOS Notification Center integration.
- **Timezone: IST hardcoded for now.** Reset time displays in IST; a configurable timezone /
  countdown is deferred (not v1).
- **Stale data / window reset → Idle.** When the cache is stale or `resets_at` has passed,
  show the Idle "waiting for Claude Code…" state, not a stale value.
- **Name `lumos` on Homebrew — free for our *tap*, but not uncontested.** No `lumos` in
  homebrew-core (only the unrelated `lume`), and a build-from-source tap is namespaced under
  our account (`Yoge5h9/lumos/lumos`, tap repo `homebrew-lumos`), so it needs no global claim.
  But the bare `brew install lumos` is not a realistic path (homebrew-core notability gate +
  GUI apps belong in casks, which need the signing/notarization we deliberately avoid), and
  the name is already used by a commercial product's tap (`teamlumos/tap/lumos`) — a
  discoverability/trademark consideration for the final public name, not a technical blocker
  for our tap. GitHub org/repo + trademark still to confirm before publishing.

## Resolved — not-on-Pro/Max (2026-07-18)

- **No reduced mode.** Lumos requires Claude Pro/Max. Setup states this up front; if
  `rate_limits` never appears at runtime, the app shows a plain "needs Claude Pro/Max" message
  instead of a broken gauge. (The plan can't be detected at install time — `rate_limits` only
  appears after the first session — so it's stated at setup and confirmed at runtime.)

## Deferred / parked (not v1 — revisit later)

- **Color-blindness** — green/amber/red is the whole signal (red-green problem). Parked; a
  colorblind-safe palette / shape cue is a post-v1 consideration.
- **Reduced motion** — respecting `prefers-reduced-motion` / macOS "Reduce motion" for Breathe
  / Bleed / adaptive glow is parked for now.

## Known technical blockers — dispositions (2026-07-18)

- **Notch overlay window** (click-through, z-order above menu bar, full-screen/Spaces, not in
  recordings) → **address during Phase 2.**
- **LED can hide behind the notch** when the menu bar is crowded → **ignore for now** (the Halo
  covers it; revisit if it bites).
- **Setup must handle every `statusLine` shape + the right settings file** → **ensure in
  Phase 2–3.** Setup runs an environment check and **tells the user what it found/did**,
  including when a prerequisite is missing (see below).
- **Homebrew SPM→`.app` bundle** assembly + ad-hoc sign → **validate later** (before publish).
- **First-launch TCC/Gatekeeper** on real notched hardware → **verify later** (needs hardware).
- **Stale-vs-reset display** → **resolved: move to Idle** (see Resolved above).

## Missing-prerequisite handling (what if the user doesn't have what we need)

Lumos must stay legible when a prerequisite is absent — `lumos setup` runs a quick environment
check and communicates plainly; the app degrades gracefully rather than showing a broken gauge:

- **No Homebrew** → can't install; the install docs give the one line to get brew first.
- **Claude Code missing / too old (< 2.1.x)** → no status-line payload; setup says so and points
  to updating Claude Code.
- **Not on Pro/Max** (API-key / Console / free) → `rate_limits` never appears, so the 5-hour
  glow can't show. **No reduced mode** — setup states Lumos needs Pro/Max, and if `rate_limits`
  never appears the app shows a plain "needs Claude Pro/Max" message instead of a broken gauge.
- **No `~/.claude/settings.json`** → setup creates one containing just the wrapped status line.
- **Existing custom status line** → wrapped non-destructively (backup + byte-for-byte restore).
- **No / thin `history.jsonl`** → Timing insight shows a cold-start "learning your pattern…"
  state instead of a suggestion.
- **`rate_limits` transiently absent** (right after `/clear`, or idle) → Idle "waiting…".
- **Non-notch Mac** → LED-only default (+ optional thin bar).
