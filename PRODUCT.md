# Product Brief — (working name: claude-notch)

> **Status: DRAFT / strawman.** This is a first pass to react to and sharpen, not a
> finalized spec. Everything here is up for debate. Decisions get locked in the
> "Decisions log" at the bottom once we agree.

---

## 1. One-liner (elevator pitch)

*A calm, ambient glow around your MacBook notch that tells you — at a glance, without
opening anything — how much of your Claude coding budget is left and when it resets.*

## 2. The problem

People on Claude Pro/Max plans (esp. heavy Claude Code users) hit an invisible wall: a
**5-hour usage window** that silently depletes. You only find out you're near the limit
when work suddenly stops. Checking means running `/usage` or opening a dashboard —
friction you won't do every few minutes. There's no **ambient, always-there** signal.

**Job to be done:** *"Let me feel how much runway I have left, and when it refills,
without breaking flow to go check."*

## 3. Target user

- **Primary:** Claude Code power users on Pro/Max — developers who live in the terminal
  and burn through the 5-hour window, and want to pace themselves.
- **Secondary:** anyone on Claude Pro/Max who wants glanceable usage awareness.
- **Not for (v1):** free-tier / API-key-only users (they don't get a 5-hour window),
  Windows/Linux (macOS notch is the whole point).

## 4. Why this, why different

- **Ambient, not a dashboard.** The value is *not looking* — peripheral color you absorb
  without focusing. Menu-bar number trackers make you read; this you just *feel*.
- **Uses the notch as a feature**, not a nuisance — turns dead hardware space into a gauge.
- **Zero-config data.** Piggybacks on data Claude Code already emits locally; no API keys,
  no login, no network, no telemetry. Private by design.
- **Smart color** = risk of getting blocked before reset (usage × time-left × burn rate),
  not just a raw %. Tells you when to *actually* worry.

## 5. Product principles

1. **Glanceable over detailed** — the default state is one color. Numbers are on-demand.
2. **Calm** — never nags, never pops. Ambient by default; escalates only when truly near-out.
3. **Private & local** — no accounts, no network, no data leaves the machine.
4. **Invisible until wanted** — no dock icon; a single menu-bar control to toggle/quit.
5. **Zero-maintenance** — install once, it just works and stays out of the way.

## 6. Feature set

### Two surfaces, one engine
Both the notch and the menu bar render the **same color logic** (usage × time-left ×
burn-rate). They are **independent surfaces** the user toggles from the menu-bar dropdown:

- **Menu-bar LED** — a small filled **colored dot** (green/amber/red). Always-on ambient
  signal *and* the click target for the menu. A solid dot (not a tinted thin outline)
  so the color reads clearly at menu-bar size. Monochrome/white is an alternate mode.
- **Notch glow** — the bigger, optional version. Off by default-able for people who find
  it distracting; they still get the menu-bar dot.

Modes the user can pick: **both** · **menu-bar dot only** · (notch only) · **minimal**
(dot, no % text). All switchable live from the menu button.

### A. The glance (data)
- **5-hour window** — color + `% used` + reset time. `[v1]` *(prototype built)*
- **Weekly (7-day) limit awareness** — the 5-hr isn't the only wall; the weekly cap bites
  and users forget it. Status line already emits `seven_day`, so it's nearly free. Dropdown
  at minimum; optional second subtle indicator. `[v1]`
- **Burn-rate / pace** — the `↑` "burning fast" cue. `[v1]` *(built)*

### B. Surfaces & control
- Menu-bar colored LED dot = always-on signal + click target. `[v1]`
- Independent toggles: **Notch glow on/off**, **menu-bar color on/off**, **show % text on/off**. `[v1]`
- Menu-bar display styles: dot-only / dot + % / monochrome icon. `[v1.1]`

### C. Smart / helpful (differentiators)
- **Predictive block warning** — "you'll be blocked ~35 min before reset at this pace."
  Projection already computed; surface it (dropdown + optional gentle notification).
  The most *useful* single thing the tool can say. `[v1.1]` **flagship**
- **Reset notification** — "You're topped up — full budget again," so users who paused
  know exactly when to resume. `[v1.1]`
- **Near-limit pulse** — slow breathe only when red with lots of time left (opt-in). `[v1.1]`

### D. Settings
- Launch at login. `[v1]`
- Timezone + 12/24h + countdown-vs-clock. `[v1.1]`
- Color thresholds / glow intensity / notch thickness / notch-outline-vs-pill. `[later]`

### Interaction & feel (locked — signed off in HTML)
- **Adaptive glow** — dim-at-rest, bright-on-attention: the Halo is calm/dim by default, blooms
  bright on hover/activity, then eases back; Alert holds a higher floor so a near-limit glow
  never fully fades. Keeps the ambient signal from being distracting. Prototyped in
  `design/interactions.html`.
- **LED: hover = info, click = control** — hovering the menu-bar dot shows a custom numbers HUD;
  clicking opens the menu. Mirrors the notch Readout's hover model.

### E. Deliberately OUT (stay calm, not analytics)
- Dollar-cost tracking & history charts (that's `ccusage`'s job).
- Multi-account, Windows/Linux, anything needing a login / API key / network.
- The product stays: **local, private, ambient — one job done beautifully.**

### Recommended cut
- **v1** = all of A + B + launch-at-login. Tight, honest, one thing done well.
- **v1.1** = the two flagship smart bits: predictive block warning + reset notification.

## 6b. Pillar 2 — Optimize (window-timing intelligence) [v2]

The 5-hour window starts on your **first message** and is otherwise idle-agnostic, so a
single trivial "primer" message controls when the window opens and resets. Aligning that
boundary to the user's peak hours = get more usable budget during the hours that matter.
Moves the product from **Observe → Optimize** (a real differentiator; keep OUT of calm v1).

**Two parts, very different difficulty:**
1. **Detect pattern (easy, robust, local):** histogram local Claude Code timestamps →
   peak hours + typical first-message time → advise the ideal primer time. Pure insight,
   private, zero fragility. *"A reset lands mid-peak; prime at ~7:30am for a fresh window
   through 10–12."*
2. **Fire the primer (constrained):** must go through the **subscription** path
   (`claude -p`, NOT a raw API call — API bills separately and doesn't touch the 5-hr
   window). Scheduling needs the Mac **awake**:
   - `pmset` wake works when **plugged in + sleeping**; macOS **defers wake on low
     battery**, **lid-closed-on-battery won't** reliably wake, **powered-off** needs flaky
     `poweron`. No local trick fixes a closed/off Mac. Cloud-side firing would need to hold
     subscription credentials server-side → **breaks the local/private principle → rejected.**

**Elegant fix — "prime on wake":** the agent detects wake/unlock and fires ONE tiny primer
the moment the user sits down (new morning, past threshold). No scheduled wake, no
closed-Mac problem. Only "start window *before* I arrive" still needs best-effort
scheduled-wake (opt-in, caveated).

**Ethics guardrail:** single, minimal, user-consented primer — never a keep-alive spammer.
Note it consumes a sliver of budget.

**Staging:** insight/advice → prime-on-wake → scheduled pre-arrival (best-effort).

## 7. Naming (to finalize)

Constraints: **no "Claude"/"Anthropic"** (trademark); short; brew-command-friendly
(lowercase, no spaces); ideally an available `.dev`/GitHub handle.

Two directions — pick a lane first, then the exact word:

**A. Descriptive** (discoverable, literal):
- `notchgauge` — clear, SEO-friendly, "notch + gauge."
- `notchmeter`, `usageglow`, `runway` (as in "how much runway left").

**B. Evocative** (brandable, memorable):
- `rimlight` — photography term for edge-lighting; *exactly* the glow effect. Distinctive.
- `aura` — ambient glow (risk: crowded name).
- `halo` — glowing ring (risk: very common).
- `ember` — a glow that warms/reddens as it burns down (nice metaphor for depletion).

**C. Pop-culture — "sees at a glance / foresees danger"** (the requested direction):

| Name | Origin | Why it fits | Watch-out |
|---|---|---|---|
| **Lumos** | Harry Potter (light/glow spell) | Literally *makes light glow* — matches the Halo perfectly; short, magical, shareable | some app collisions |
| **Heimdall** | Marvel/Norse | All-seeing guardian + warning horn = glance + alert | existing self-hosted "Heimdall" dashboard |
| **Precog** | Minority Report | The *predictive* "you'll be blocked soon" foresight; brandable, techy | slightly niche |
| **Patronus** | Harry Potter | A **glowing** guardian summoned against danger = glow + protection | long-ish |
| **Palantír** | LOTR | "Seeing-stone" — see distant things at a glance | ❌ Palantir trademark — avoid |
| **JARVIS / FRIDAY** | Marvel | AI that watches your levels & warns you | ❌ heavily trademarked — avoid |
| **Sneakoscope** | Harry Potter | Lights up near danger — an ambient warning device | hard to spell/say |

**Top picks:** **`Lumos`** (the glow — most on-brand for the Halo, catchy, easy to share) or
**`Heimdall`** (the watch-and-warn function). `Precog` if we want to lead on the predictive
angle. Descriptive fallback: `notchgauge`.

## 8. Distribution (already decided)

- **Homebrew build-from-source tap** — `brew install <you>/<name>/<name>` then
  `<name> setup`. Compiles locally → no Gatekeeper prompt, **free**, no Apple Developer
  account. `brew upgrade` / `<name> setup --uninstall` for lifecycle.
- **Free / no code-signing** for now; leave room to add a signed, notarized prebuilt
  cask later if non-developer demand appears.
- **Public OSS**, permissive license (MIT), under a new non-"Claude" name.

## 8b. First release (v1) — proposed lock

Ship a tight, honest "ambient glance" product. Everything else is a fast-follow.

**In v1.0:**
- **Halo** — 5-hr color ring (Calm/Watch/Alert/Idle), risk-based color model.
- **Readout** on hover with the **Bleed** animation — `% used · resets … IST`.
- **LED** — menu-bar colored dot (same logic).
- **Independent toggles** (from the menu): Halo on/off · LED color on/off · %-text on/off.
- **Weekly (7-day)** figure in the dropdown.
- **Launch at login.**
- **One-command setup** (wraps the status line non-destructively + login item + launch),
  fully reversible. Intuitive, effortless — per the core requirement in `CLAUDE.md`.
- **Homebrew build-from-source** install.

**Deferred (v1.1+):** predictive block warning (Nudge), reset notification (Refill),
context-rot coaching (Nudge), Breathe, settings (timezone/format/thresholds), display styles.
**Deferred (v2):** the Optimize pillar — window-timing insight → Prime-on-wake → scheduled prime.

## 8c. Updates & auto-update

Because we ship **build-from-source via Homebrew**, updates ride the brew rails:

1. **Canonical: `brew upgrade <name>`.** We tag a release + bump the formula (new `url` +
   `sha256`); users get it on upgrade. `brew` auto-runs `brew update` periodically, so update
   *discovery* is free — no phone-home needed. Keeps the app 100% network-free.
2. **Nicety — in-app "update available" (opt-in):** a once-a-day check of the GitHub Releases
   API; if newer, the menu shows *"Update available (vX.Y)"* → one click runs `brew upgrade`
   and relaunches. This is the ONE optional network call; off by default to preserve the
   no-network principle, and it sends nothing but a version query.
3. **Optional auto-update (opt-in):** a toggle installs a small weekly `brew upgrade` LaunchAgent.

**Not using Sparkle** (the usual macOS auto-updater): it's built around downloading *prebuilt
signed* binaries → reintroduces Gatekeeper/notarization, which we deliberately avoid. Staying
on brew keeps updates free, trusted, and unsigned-friendly.

## 9. Open decisions

**Resolved (2026-07-18 — see [`DECISIONS.md`](./DECISIONS.md)):** name = **Lumos** (free on
Homebrew); v1 scope = glance + all 3 notification types (calm contract); audience = Claude Code
power users on Pro/Max; **glow tracks the 5-hour window only** (weekly shown in the dropdown);
**context warning at 40%**; **notifications pill-only**; **timezone IST for now**; stale/reset
→ Idle; non-notch = LED-only default + optional thin bar; distribution = Homebrew from source.

**Also resolved:** **not-on-Pro/Max** → no reduced mode; setup states Lumos needs Pro/Max and
the app shows a plain "needs Pro/Max" message otherwise.

**Deferred / parked (not v1):** color-blindness treatment and reduced-motion support.

## Decisions log

The full running log lives in [`DECISIONS.md`](./DECISIONS.md). Headline locks (2026-07-18):

- **Name Lumos** (MIT, public OSS); working folder `claude-notch` for now (rename deferred).
- **v1.0 = ambient glance + all 3 notification types** (Context / Timing / Tip), under a
  calm contract (per-type daily cap, per-notification "don't show again", quiet hours,
  master off). Default surfaces: **Notch + LED both on**.
- **Non-notch Macs:** auto-detect; **LED-only default** + optional **thin top-center glow
  bar**; full-width glow and floating pill rejected.
- **Data:** `~/.claude/lumos/cache.json` keyed by `session_id`; context warning fires on max
  context % across non-stale sessions; timing from `history.jsonl`; setup is backup-first,
  abort-on-no-safe-backup, byte-for-byte reversible.
- **Distribution:** Homebrew build-from-source, ad-hoc signed; `swift build` **verified
  green on Command-Line-Tools-only** (no full Xcode). Updates = one-tap `brew upgrade`.
