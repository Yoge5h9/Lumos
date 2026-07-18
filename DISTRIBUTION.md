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

## Install (Homebrew, prebuilt universal binary)

- We publish a **tap** (a GitHub repo, `homebrew-lumos`) with a **formula** (`lumos.rb`).
- Install: `brew install <you>/lumos/lumos` → then `lumos setup`.
- The formula **downloads a prebuilt, ad-hoc-signed universal `Lumos.app`** (one artifact
  covers Apple Silicon + Intel, macOS 13+) built by `scripts/release.sh` and attached to the
  GitHub Release. **No compiler, no Command Line Tools, no Xcode** needed on the user's
  machine — install is a few-second download+extract on any supported macOS.
- **Still Gatekeeper-free, still no $99/yr Apple account.** A Homebrew *formula* installs into
  the Cellar **without** the `com.apple.quarantine` xattr, and Gatekeeper's blocking prompt
  only fires on quarantined files. An ad-hoc signature (which `codesign -s -` provides, enough
  to satisfy Apple-Silicon's "must be signed to run") + no quarantine = the app launches with
  **no "unidentified developer" popup**. Verified on real hardware (`open Lumos.app` launches
  clean; the app is non-quarantined post-install).
  - This is the key distinction from a **cask**: a cask downloads a `.app` that macOS *does*
    quarantine → prompt → would need notarization. A formula-hosted binary does not.
- **Source build is still available** for anyone who prefers to compile: `brew install --HEAD`
  builds straight off `main` via `swift build` (needs a current-enough CLT).

Why the switch from build-from-source (the original plan): compiling on the user's machine
made **every** install depend on a current toolchain — Homebrew hard-refuses to build a source
formula when the Command Line Tools lag the running macOS. That put a multi-GB CLT update in
front of first use, which fails the "effortless to install" bar. The prebuilt path removes that
wall entirely while keeping every other property (free, no account, no Gatekeeper prompt).

## Updates — how they work

"Auto-update" here realistically means **auto-detect + one tap**, not a fully-silent swap
(silent updates require code-signing + notarization, which we deliberately avoid):

1. **Discovery is free.** Homebrew periodically runs `brew update` on its own, so it learns
   a new Lumos version exists — no phone-home from us.
2. **Applying is one command:** `brew upgrade lumos` re-downloads the new prebuilt binary
   (no recompile) and swaps it in.
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
| Command Line Tools | 0 MB (default) | **Not required** for the default prebuilt install. Only the optional `--HEAD` source build needs them. |
| Transient files | ~1 MB | The downloaded tarball; brew cleans up after. |

**Net:** the *incremental* install is **~a few MB** (a ~900 KB binary download), on top of
Homebrew if you don't already have it. No toolchain, no compile step.

## Concerns to be aware of

- **Homebrew is a prerequisite.** The user must have `brew`. Biggest friction for a
  non-brew user (one setup line first).
- **We own the build now.** The prebuilt artifact is our responsibility: `scripts/release.sh`
  must produce a genuinely **universal** binary pinned to the **macOS 13** floor and bundle
  every asset — a bad arch or a raised min-OS crashes older Macs on launch instead of erroring
  at build time on the user's side. Mitigation: the script verifies arches + a smoke launch
  before we tag.
- **Intel vs Apple Silicon paths differ** (`/usr/local` vs `/opt/homebrew`) — never hardcode
  the brew path in the app or login item. (The binary itself is universal, so both run natively.)
- **Prebuilt is fine *as a formula*, not a cask.** Gatekeeper-free relies on Homebrew not
  quarantining formula files + an ad-hoc signature. If we ever ship a **cask** instead, that
  breaks and we'd need notarization.
- **Not eligible for homebrew-core.** A formula that installs a prebuilt binary can't go into
  the core tap (they require source builds or official bottles). Fine for our personal tap; if
  core is ever wanted, switch to CI-built bottles.
- **Corporate/MDM Macs** with strict policy may still refuse a non-notarized app regardless of
  quarantine — only full notarization fixes that (the cask escape hatch below).
- **Trust:** users run a binary we built rather than compiling it themselves. Mitigation: **open
  source (MIT), reproducible `scripts/release.sh`, published sha256, no network calls** — and
  `--HEAD` remains for anyone who prefers to compile.
- **Not the Mac App Store** — no sandbox, no store discovery. Correct trade for a dev tool;
  discovery is "share the brew command."

**Escape hatch for later:** if non-developer demand appears, add a signed, notarized
prebuilt **cask** alongside the source tap (needs the Apple account, ~$99/yr) — a ~5–10 MB
download with no toolchain required. Only worth it when demand proves it.
