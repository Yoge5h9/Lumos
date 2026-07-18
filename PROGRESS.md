# Lumos — Build Progress (living log)

> The single place to see **where the build actually stands**. Update this after each
> meaningful chunk of work (see the "Living docs" rule in [`CLAUDE.md`](./CLAUDE.md)).
> Companion to [`PLAN.md`](./PLAN.md) (the plan) and [`DECISIONS.md`](./DECISIONS.md) (the locks).
>
> **Last updated:** 2026-07-18 (stale redesign + onboarding/pill polish landed; Homebrew prep in progress)

## 2026-07-18 (later) — Stale redesign, compact pill & onboarding landed

Ported to Swift + build-green (on hardware), superseding the earlier on-hardware findings:
- **Stale = desaturated-dimmed, static, frozen numbers** (5-min threshold; desat 60% / dim 45% via
  `StaleStyle`) with a blended `stale · updated Xm ago` sub-label **below** the Readout — replaces the
  old invisible-gray Idle. "waiting for Claude Code…" is now reserved for the no-data-ever case.
- **Compact Readout pill** `NN% · <relative> to reset` (e.g. `85% · 9m to reset`), ~notch width, 10px
  below the notch; full detail (absolute time, weekly) moved to the click HUD.
- **Onboarding revamped** — word-wrap clipping fixed; Harry-Potter-flavored copy ("Lumos lights up the
  dark…"); green dot removed (a woody wand-glow mark is in design); reassurance-tail copy trimmed; a
  high-level "updates as you use Claude Code in the terminal" note added (also in `lumos setup` output).
- **Notch is screen-capturable** (`sharingType = .readOnly`).
- **Terminal-Claude-Code-only data** confirmed (status line doesn't fire in Desktop/web/IDE) — surfaced
  honestly via the stale state + high-level copy; cross-surface network sync rejected (see DECISIONS).
- **Homebrew release prep in progress** (Info.plist, CLT-only formula to drop the Xcode dep, secret
  scan clean); publish gated on user approval, after the icon + design-HTML cleanup land.

## Status at a glance

| Phase | Area | State |
|---|---|---|
| 1 | Data / cache / `setup` (`LumosCore`) | ✅ done & tested |
| 2 | ColorModel (risk/color model) | ✅ done, harness-verified, Opus-reviewed |
| 2 | Menu-bar app (agent, LED, menu, toggles) | ✅ done, `swift build` green |
| 2 | Notch overlay + Halo/Bloom · Readout/Bleed · non-notch fallback · burn-sampler · onboarding · login item | ✅ built + build-green (see on-hardware findings) |
| 3 | Notification brain (calm-contract engine) | ✅ done, Opus-reviewed (1 medium bug found + fixed) |
| 3 | Notification delivery (pill wired to engine) | ✅ integrated |
| 4 | Updater (opt-in version check + `brew upgrade`) | ✅ done + wired |
| 4 | Packaging (Info.plist, assemble-app.sh, formula, tips.json) | ✅ scaffolded |
| 4 | Homebrew tap repo (`Yoge5h9/homebrew-lumos`) | ✅ public, pushed (placeholder url/sha) |
| 4 | `lumos setup` launches app + enables login item | ✅ added (`--no-launch` opt-out) |
| — | First on-hardware run (Mac16,12) | ✅ ran; crash fixed; findings below |
| 4 | First release (make repo public + tag v0.1 + fill formula) | ⬜ not started |

## Verified done

- **`LumosCore` data layer** — cache read/write/aggregate, `ingest`, `history.jsonl` timing,
  non-destructive `setup`/`--uninstall`.
- **`ColorModel`** — risk model from `DESIGN.md`; `UsageState` + single-source hex palette;
  24-assertion harness incl. fresh-window-never-Alert; Opus review: no defects.
- **Notification engine** (`NotificationEngine.swift`) — full calm contract (40% Context +
  per-session de-dupe, daily caps, quiet hours, both "don't show again" levels, master off, tip
  rotation). Opus review found **1 medium bug** (a wrong-typed field in the state file silently
  reset master-off/quiet-hours) — **fixed** (per-field tolerant decode).
- **Updater** — pure semver compare, network behind a protocol, once-a-day throttle,
  `brew upgrade` command. Harness-verified.
- **Menu-bar app + notch UI** (`Sources/lumos/`) — single binary (no-arg → GUI; `ingest`/`setup`
  intact); `.accessory`; LED dot; notch overlay (`NSPanel`, level `mainMenu+1`, click-through,
  all-Spaces, `sharingType=.none`); Halo/Bloom (CALayer); Readout + Bleed; non-notch fallback;
  onboarding; login item. Engine + updater wired into the delivery/update seams.
- **Lightweight hardening** — event-driven `DispatchSource` cache watch (150ms debounce, re-arms
  on atomic replace), coarse 60s tick only for stale/reset transitions, glow **static at rest**
  (animates only on state change/hover), pause on display sleep. Orphan `LumosApp` target removed.
- **Tips** — externalized to `Resources/tips.json` (Bundle.main), embedded `defaultTips`
  fallback if missing/corrupt. 13 tips seeded from `TIPS-RESEARCH.md` YES picks. Living section.
- **Crash fix** — onboarding `NSWindow` was `isReleasedWhenClosed=true` + ARC-owned → double-free
  → SIGSEGV on close. Fixed (`isReleasedWhenClosed=false`); verified: closed onboarding, process
  survived, no new crash report. Layout also rebuilt (Auto Layout, no clipping).

## On-hardware run (Mac16,12 MacBook Air M4) — 2026-07-18

- ✅ **Geometry works** — `lumos diagnose`: notch detected 179×32pt, corner-radius 14, level 25.
- ✅ **Data pipeline works** — `lumos setup` wrapped the real status line; `cache.json` populated
  with real usage (5h 45%, 7d 58%, ctx 37%, Opus 4.8 1M).
- ✅ **GUI renders** — onboarding window drew; menu-bar LED shows.
- ✅ **Crash fixed & verified** (see above).
- ⚠️ **Findings to fix (v1 polish):**
  1. **Idle is invisible** — Idle Halo is dim gray on a black notch → reads as "notch not
     working." Give Idle a perceptible treatment (faint but visible glow, and/or clearer LED).
  2. **`setup` mid-session** — data begins on the **next Claude Code interaction** (official docs: the
     status line **hot-reloads**, it is *not* session-start-only — earlier claim corrected). The
     on-hardware "no data until a new session" is most likely the documented settings-strip bug
     (anthropics/claude-code#62486 — CC periodically rewrites `settings.json` and drops `statusLine`)
     and/or the workspace **trust gate** (status line stays blank until the folder's trust dialog is
     accepted). Remedy: `setup` closing line — "your glow starts on your next Claude Code interaction;
     if it stays dim, start a fresh session and make sure this folder is trusted." **Plus a self-heal:**
     Lumos periodically re-verifies its `statusLine` entry survived and re-wraps non-destructively if
     CC stripped it (consistent with "wrap, never replace").
  4. **Only the terminal CLI runs the status line** — VS Code / JetBrains / Desktop-app *Code tab* do
     NOT execute `statusLine` (confirmed gaps; Desktop Code has its own usage ring). Lumos's audience is
     terminal Claude Code users — document as a known limitation, don't silently show nothing.
  3. **Notch Halo not yet confirmed visible in a live (non-Idle) color** on hardware — needs a
     look with fresh non-stale data (was only ever seen stale/Idle).

## Confirmed non-issues

- **App does NOT use Apple Events / System Events** (grep-clean) → the shipped app will **not**
  trigger a TCC "control System Events" prompt. The prompt seen during dev came from `osascript`
  test/quit commands (Claude Code), not Lumos. Notch overlay uses mouse monitors only (no
  Accessibility TCC).

## Repos

- **`Yoge5h9/Lumos`** — the app. **PRIVATE** (must go public for any `brew` install path).
- **`Yoge5h9/homebrew-lumos`** — the tap. **Public**; formula `url`/`sha256` are placeholders.

## Before first release (v0.1) — checklist

- [x] Land + integrate UI wave, notification engine, updater; `swift build` green
- [x] Fix the launch crash; verify on hardware
- [x] Commit + push this session's work to `Yoge5h9/Lumos` (`50458c4`)
- [x] Stale redesign (supersedes Idle-visibility) + high-level "terminal" note in `setup`/onboarding
- [x] Wand Tip + Bloom app icon (`.icns`) + onboarding mark
- [x] Confirm live color on hardware (amber at 85% seen)
- [x] `Yoge5h9/Lumos` **public**; secret scan clean; MIT `LICENSE` present
- [x] `Info.plist` bundle id `com.yoge5h9.lumos` + version `0.1.0`
- [x] **Tagged `v0.1.0`** + GitHub release; tarball `sha256` filled + **tap pushed**
- [x] `depends_on xcode` **dropped** (CLT-only validated) — no 15 GB Xcode for users
- [x] Formula resolves (`brew info` → `stable 0.1.0`); brew fetched tarball + verified sha256
- [ ] `brew install --build-from-source` end-to-end — **blocked on THIS machine only** by Homebrew's
      CLT-version gate ("CLT too outdated"); not a formula defect. Run on a machine with current CLT.
- [ ] Run the Swift Testing suite under Xcode once (deferred; CLT can't run it)
