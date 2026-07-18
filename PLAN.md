# Lumos — v1.0 Plan (features, requirements, build order)

> Working name `claude-notch` → public name **Lumos**. This is the agreed build plan for the
> first release. Product thinking lives in [`PRODUCT.md`](./PRODUCT.md); visual language in
> [`DESIGN.md`](./DESIGN.md); the non-negotiable contract in [`CLAUDE.md`](./CLAUDE.md);
> **live build status in [`PROGRESS.md`](./PROGRESS.md)**.

## Context

`claude-notch` (public name **Lumos**) is greenfield: the repo is docs + one HTML
prototype (`design/showcase.html`), **no Swift yet**. Lumos is a calm, ambient macOS tool
that shows — at a glance — how much of the Claude 5-hour usage window is left, plus a new
**"aware-of-you" notification brain** (context-rot warning, window-timing insight, rotating
pro-tips). The founding principle is *calm, never nags, never pops uninvited*, so the
notification system ships under a strict **calm contract** (opt-out per type + per
notification, daily caps, quiet hours, master off).

This plan reflects decisions taken in-session and two research passes (Claude Code
status-line schema; unsigned macOS distribution + auto-update). Key research facts:

- **3.1 is feasible & cheap.** Claude Code emits `context_window.used_percentage` and
  `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` per session, each JSON
  tagged with `session_id`. A wrap-and-tee status-line script (a **working reference
  already exists** at `~/.claude/statusline-command.sh` → `~/.claude/notch-usage.json`)
  can cache per-session context, so Lumos watches *all* live sessions.
- **Idle caveat (shapes UX).** The status line goes quiet when a session is idle and never
  runs when Claude Code is closed. Treat cache mtime as a staleness signal → show the
  **Idle "waiting for Claude Code…"** state; always trust the absolute `resets_at` epoch.
- **3.2 source.** `~/.claude/history.jsonl` (epoch-ms, project-tagged prompts) is the clean
  local histogram source for peak-hours / best-prime-time. Cold-start: needs a few days.
- **Distribution.** Source-build Homebrew **Formula** (not cask) = locally compiled = no
  quarantine = **zero Gatekeeper dialog**. Ad-hoc sign (`codesign -s -`, no Apple account).
  Update = in-app GitHub version check → one-tap `brew upgrade` (not Sparkle). Login item
  via `brew services` + in-app `SMAppService.mainApp.register()`. Build via **SPM +
  hand-assembled `.app` bundle** (keeps install light — avoids a multi-GB full-Xcode dep).

### Locked decisions
- Name **Lumos**. v1.0 = ambient glance **+ all 3 notification types**.
- Personality: aware-of-you, calm-contract. Notif caps: **per-type ~1 push/day** (Context
  may re-fire for a genuinely new session crossing the threshold); each muteable + "don't
  show again" + master off + quiet hours.
- Coaching (Timing/Tips): **gentle push, capped**, with "seen-it" memory; Tips rotate an
  updatable list.
- **All Macs.** Auto-detect notch geometry; non-notch fallbacks to be chosen from an HTML
  showcase of 4 treatments (top-center glow bar · full-width top-edge glow · LED-only ·
  floating ambient pill).
- Default surfaces out of the box: **Notch Halo + LED both on**.

---

## Approach (phased; visuals-first per the CLAUDE.md HTML rule)

### Phase 0 — HTML design showcases (FIRST deliverable, before any Swift)
Extend `design/` so every new look can be *felt* in a browser and iterated with the user.
Build (self-contained, offline, live controls per `CLAUDE.md`):
- `design/non-notch.html` — the 4 non-notch fallbacks **side by side** (top-center glow
  bar, full-width top-edge glow, LED-only, floating pill), each in Calm/Watch/Alert/Idle.
- `design/notifications.html` — the notification pill (extends the **Bleed** language):
  **Context** ("context at 38% — quality dips past ~40%; start a fresh session or write a
  handoff & /compact"), **Timing** ("you peak ~11am — prime your window ~8am"), **Tip**
  (rotating pro-tip). Show enter/dismiss/"don't show again" affordances + stacked vs single.
- Extend `design/showcase.html` — palette refinement, menu dropdown mock (toggles: Notch /
  LED / %-text / per-type notifications / quiet hours / master off), weekly (7-day) row.
- **Gate:** user reviews/selects in-browser; lock the visual language before Swift.

### Phase 1 — Data & cache layer
- Define cache at `~/.claude/lumos/cache.json` (Lumos-owned; does **not** clobber the
  existing `notch-usage.json`). Schema: per-`session_id` entries `{five_hour, seven_day,
  context_window.used_percentage, context_window_size, model, updated_at}`, pruned by
  staleness.
- `lumos setup` **non-destructively** wraps the existing `statusLine` in
  `~/.claude/settings.json`: back it up, wrap the command so it still runs the user's
  original status line AND tees the JSON fields into the cache (mirrors the proven
  `statusline-command.sh` pattern). Fully reversible (`lumos setup --uninstall` restores
  the backup).
- Timing insight reads `~/.claude/history.jsonl` **read-only** → hour-of-day histogram.
- Guard every field (`rate_limits` absent for non-Pro/Max; `context_window.used_percentage`
  null early/post-compact). Missing/stale → Idle.

### Phase 2 — Core app (menu-bar agent + surfaces)
- SPM executable, `NSApp.setActivationPolicy(.accessory)`, `LSUIElement` in Info.plist —
  no dock icon; single `NSStatusItem` menu.
- **Hardware auto-detect:** on launch + every display reconfigure, enumerate `NSScreen`,
  find the notched screen via `safeAreaInsets.top` / `auxiliaryTopLeftArea/RightArea`, read
  actual notch width/height/corner-radius, draw the **Halo** to fit. Non-notch → chosen
  fallback surface. Follow display changes / clamshell.
- **LED** (`NSStatusItem` colored dot, same color logic) + **Halo/Bloom** + **Readout**
  pill with the **Bleed** animation on hover.
- **Color model** (reuse `DESIGN.md`): risk-of-block = usage × time-left × burn-rate;
  escalation gated to ≥45% used (ramp to 75%); burn needs ≥3 samples over ≥10 min — a fresh
  window can never be Alert (permanent regression check). States Calm/Watch/Alert/Idle
  (`#30D158`/`#FFD60A`/`#FF453A`/`#8C8C8C`).
- Weekly (7-day) figure in the dropdown.

### Phase 3 — Notification brain (calm contract)
- Three types — **Context / Timing / Tip** — behind an engine that enforces: per-type daily
  cap, per-session de-dupe for Context, quiet hours, "don't show again" (per type + per
  specific notification), master off. All state persisted locally.
- **Context (3.1):** watch max context% across non-stale sessions; fire once when a session
  crosses **40%** (the point quality starts dipping; remedy: fresh session / handoff doc +
  `/compact`). Delivered as the pill only — no Notification Center.
- **Timing (3.2):** after enough history, surface "prime ~HH:MM" — gentle push capped, and
  also available passively in the dropdown ("Your best prime time").
- **Tip (3.3):** rotating, updatable list with seen-it memory; gentle push (≤1/day) + a
  "Today's tip" dropdown row.
- Delivery = the notch/fallback **notification pill** (from Phase 0), dismissible.

### Phase 4 — Setup, install, updates, onboarding
- Homebrew **tap** `homebrew-lumos` + `Formula/lumos.rb` (source build, ad-hoc sign,
  hand-assembled `.app`). Install = `brew install <you>/lumos/lumos` → `lumos setup`.
- **First-run onboarding** (one screen): what powers Lumos (reads Claude Code's local
  status-line data, no network/API keys), the surfaces, and the toggles — satisfies
  "explain what we use + basic features."
- Launch-at-login via `brew services` + in-app `SMAppService` toggle.
- **Updates:** opt-in daily GitHub version check → calm "Update available" menu row →
  one-tap `brew upgrade lumos` + relaunch. Optional weekly auto-`brew upgrade` LaunchAgent.
- **Reversibility:** `lumos setup --uninstall` restores the status-line backup, removes the
  login item + cache; `brew uninstall`.
- Degrade legibly: not Pro/Max / no data / stale → human copy, never blank/error code.

### Phase 5 — Docs & CLAUDE.md
- Add to `CLAUDE.md`, per user request: a **"Collaboration & critique"** principle (Claude
  should actively critique the user's product points and think *with* them) and reinforce
  the **"showcase UI/UX in HTML before finalizing"** rule as non-negotiable.
- Record locked choices in `PRODUCT.md` "Decisions log"; update `DESIGN.md` lexicon with the
  notification pill + chosen non-notch surface.

---

## Critical files (to create)
- `design/non-notch.html`, `design/notifications.html`, extend `design/showcase.html`
- `Package.swift`; `Sources/Lumos/` — `main.swift` (agent + status item), `NotchWindow.swift`
  (Halo/Bloom geometry + fallbacks), `Readout.swift` (Bleed pill), `ColorModel.swift`
  (risk model + burn samples), `Cache.swift` (read `~/.claude/lumos/cache.json`),
  `Notifications.swift` (calm-contract engine), `Timing.swift` (history.jsonl histogram),
  `Setup.swift` (`lumos setup` / `--uninstall`), `Onboarding.swift`, `Updater.swift`
- `Resources/Info.plist` (`LSUIElement`), app-bundle assembly script
- `homebrew-lumos/Formula/lumos.rb` (separate tap repo)
- `CLAUDE.md`, `PRODUCT.md`, `DESIGN.md` edits

## Reuse
- `~/.claude/statusline-command.sh` — proven wrap-and-tee reference for the setup wrapper.
- `design/showcase.html` — existing Halo/Bloom/Readout/Bleed CSS + color model to extend.
- `DESIGN.md` color model + gating rules — port verbatim to `ColorModel.swift`.

## Phase 2 kickoff — agent handoff

Point a Phase 2 agent at these, in order:

1. **Read first (context):** `CLAUDE.md` (contract + **Development safety** — never touch the
   real `~/.claude`), this `PLAN.md` §"Phase 2 — Core app", `DECISIONS.md` (locked + open items
   + blockers), `DESIGN.md` (lexicon, states, **color model**), `DISTRIBUTION.md` (app shape).
2. **The look is the source of truth:** the agreed visuals live in `design/*.html`
   (`showcase`, `notifications`, `non-notch`, `interactions`) — open `design/index.html` and
   port the *felt* look; do not reinvent it. Reuse exact tokens/colors from there.
3. **Build on the data layer, don't rebuild it:** `Sources/LumosCore/` already provides the
   cache reader + multi-session aggregate (`CacheAggregator`), the `history.jsonl` timing
   histogram (`TimingAnalyzer`), and `ingest`/`setup`. Phase 2 is the **UI/app** that reads
   `CacheAggregator` and renders — it must not change the cache schema.
4. **First slices (smallest shippable, in order):** (a) menu-bar agent scaffold (`.accessory`,
   `LSUIElement`, `NSStatusItem` + LED dot colored from `CacheAggregator`); (b) the menu with
   toggles; (c) `ColorModel` port from `DESIGN.md`; (d) the notch overlay window + Halo/Bloom
   with geometry auto-detect; (e) Readout + Bleed; (f) non-notch fallback (LED-only + thin
   bar). Notifications (Phase 3) come after the surfaces render.
5. **Keep the blockers in mind** (`DECISIONS.md`): notch overlay click-through/z-order,
   LED-behind-notch, TCC on real hardware — and the **open color-model decisions** (weekly-in-
   glow, threshold, colorblind). Flag rather than guess if they surface.
6. **Constraints:** self-contained per `CLAUDE.md`; verify with `swift build`; no destructive
   actions; visual changes still go through an HTML preview first.

## Verification (end-to-end)
- **Phase 0:** open the HTML showcases in a browser; confirm every state renders; iterate
  with the user until the look is signed off.
- **Data:** run `lumos setup`; in a real Claude Code session confirm `~/.claude/lumos/
  cache.json` fills with per-session fields; verify the original status line still renders
  and `settings.json` backup exists; `--uninstall` restores it byte-for-byte.
- **App:** `swift build`; launch; verify no dock icon, LED + Halo appear, hover shows the
  Bleed Readout, colors track the risk model. Force a fresh window (2% → Calm, never Alert).
- **Notifications:** simulate context ≥35% in one session → one Context pill; verify caps,
  "don't show again", quiet hours, master off; Timing/Tip appear ≤1/day.
- **Hardware:** test notched + non-notch + external-display/clamshell reconfig; confirm the
  overlay re-homes to the right screen and no TCC/Gatekeeper dialog appears on first launch.
- **Distribution:** `brew install --build-from-source` from the tap on a clean machine →
  zero Gatekeeper prompt; `brew services start lumos`; simulate a newer tag → update row →
  `brew upgrade` path works.
