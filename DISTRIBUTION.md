# Lumos — What it is, install, updates & size

> Captures the app shape, install/update mechanics, footprint, and the concerns to be aware
> of. Companion to [`PRODUCT.md §8`](./PRODUCT.md) (distribution) and [`PLAN.md`](./PLAN.md).

## What Lumos is (app shape)

Lumos is a native macOS **menu-bar app** (Swift + AppKit) — not a command-line tool. It has
**no dock icon and no normal window**. It appears only as:

- a **colored dot in the menu bar** (the LED), and
- a **glow drawn around the notch** (a transparent, always-on-top overlay).

Mental model: like Stats, Ice, Bartender, or the battery icon — you never "open" it, it's
just quietly present.

There is a small CLI helper — `lumos setup` and the status-line wrapper — but that's just
**one-time plumbing** to wire it up. The product is the GUI app.

### Runs in the background — what that means
- A **long-running per-user background process** (a launchd *user agent*) that starts at
  login and stays running quietly. No dock icon, not in ⌘-Tab (`LSUIElement` / `.accessory`).
- Does almost nothing most of the time: reads one small local cache file (every few seconds
  or on change), recomputes the color, redraws. **Low CPU, ~20–60 MB RAM, no network.**
- A **user agent, not a system daemon** — runs as you, only while logged in, no special
  privileges, touches nothing outside your own files.

## Install (Homebrew build-from-source)

- We publish a **tap** (a GitHub repo, `homebrew-lumos`) with a **formula** (`lumos.rb`).
- Install: `brew install <you>/lumos/lumos` → then `lumos setup`.
- The formula **compiles Lumos from source on your machine**. Because it's built locally
  (not "downloaded from the internet"), macOS never flags it → **no "unidentified
  developer" Gatekeeper popup**, and we skip the $99/yr Apple Developer account. That trick
  is the whole reason for this route.

## Updates — how they work

"Auto-update" here realistically means **auto-detect + one tap**, not a fully-silent swap
(silent updates require code-signing + notarization, which we deliberately avoid):

1. **Discovery is free.** Homebrew periodically runs `brew update` on its own, so it learns
   a new Lumos version exists — no phone-home from us.
2. **Applying is one command:** `brew upgrade lumos` re-fetches source and recompiles.
3. **Nicety (opt-in):** the app checks GitHub releases once a day; if newer, it shows a calm
   **"Update available (vX.Y)"** menu row → one click runs `brew upgrade` and relaunches.
   Optional weekly auto-upgrade toggle.

## Size / footprint

| Component | Size | Notes |
|---|---|---|
| **Lumos.app** (the app itself) | **~2–8 MB** | Small Swift+AppKit binary + Info.plist + assets. All that's *Lumos*. |
| Swift runtime | 0 MB | Ships with macOS (ABI-stable) — not bundled. |
| RAM while running | ~20–60 MB | Idle background agent; negligible CPU. |
| Homebrew (prerequisite) | ~300 MB–1 GB | One-time, shared across all brew apps. Most devs already have it. |
| Command Line Tools (to compile) | ~1–2 GB | One-time, reusable. We target this, **not** full Xcode (7–15+ GB). |
| Transient build files | tens–low-hundreds MB | Only during install/upgrade; brew cleans up after. |

**Net:** if you already have brew + Command Line Tools (typical for our target user), the
*incremental* install is **~a few MB**. From a bare Mac, the one-time prerequisites dominate
at ~2–3 GB — but that's general dev tooling you'd reuse, not weight Lumos adds.

## Concerns to be aware of

- **Homebrew is a prerequisite.** The user must have `brew`. Biggest friction for a
  non-brew user (one setup line first).
- **First install compiles** → not instant (seconds–minute) and needs Apple's build
  toolchain. We target the lighter **Command Line Tools**, not full Xcode.
- **Every update recompiles** → brief CPU/time cost each `brew upgrade`.
- **Intel vs Apple Silicon paths differ** (`/usr/local` vs `/opt/homebrew`) — never hardcode
  the brew path in the app or login item.
- **Stay source-only.** Zero Gatekeeper works *because* it's compiled locally. Handing out a
  prebuilt `.app` would get flagged — so we distribute only via the tap.
- **Trust:** users run a recipe that compiles code on their machine. Mitigation: **open
  source (MIT), auditable, no network calls** — state this loudly in the README.
- **Not the Mac App Store** — no sandbox, no store discovery. Correct trade for a dev tool;
  discovery is "share the brew command."

**Escape hatch for later:** if non-developer demand appears, add a signed, notarized
prebuilt **cask** alongside the source tap (needs the Apple account, ~$99/yr) — a ~5–10 MB
download with no toolchain required. Only worth it when demand proves it.
