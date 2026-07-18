# Lumos — Build Progress (living log)

> The single place to see **where the build actually stands**. Update this after each
> meaningful chunk of work (see the "Living docs" rule in [`CLAUDE.md`](./CLAUDE.md)).
> Companion to [`PLAN.md`](./PLAN.md) (the plan) and [`DECISIONS.md`](./DECISIONS.md) (the locks).
>
> **Last updated:** 2026-07-18 (first on-hardware run + crash fix)

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
  2. **`setup` mid-session doesn't flow data until a NEW Claude Code session** — the wrapper only
     fires in a fresh session. `setup` should tell the user to start a new session / restart.
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
- [ ] Commit + push this session's work to `Yoge5h9/Lumos` (was 18 files uncommitted)
- [ ] Fix Idle visibility + add `setup` "start a new session" guidance (on-hardware findings)
- [ ] Confirm the notch Halo renders in a live color on hardware
- [ ] Make `Yoge5h9/Lumos` public (secret-scan first; MIT `LICENSE` present)
- [ ] Fill `Info.plist` bundle id + version `0.1.0`
- [ ] Tag `v0.1.0`; download tarball → `shasum -a 256` → fill formula `url`+`sha256`; push tap
- [ ] `brew install --build-from-source Yoge5h9/lumos/lumos` end-to-end (no Gatekeeper prompt);
      resolve `depends_on xcode` → CLT-only if it builds
- [ ] Run the Swift Testing suite under Xcode once (deferred; CLT can't run it)
