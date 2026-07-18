# DESIGN.md — visual language, states & animation

Shared vocabulary so we can talk about the look precisely. Preview everything in
`design/showcase.html` before it goes into Swift (see `CLAUDE.md`).

## The lexicon

| Name | What it is | Status |
|---|---|---|
| **Halo** | The glowing colored ring tracing the notch's sides + bottom. The always-on ambient signal. | built |
| **Bloom** | The soft outer glow/light-bleed behind the Halo (its diffuse halo of light). | built |
| **Readout** | The info pill: `NN% used · resets H:MM AM/PM IST`. Appears on hover. | built |
| **Bleed** | The animation of the Readout **extruding out of the notch** — a notch-width sliver grows down + out to full width (slight overshoot), retracts on exit. | built |
| **LED** | The menu-bar colored dot — a small mirror of the Halo color; always available even if the Halo is off. | planned |
| **Breathe** | Slow pulse of the Halo/Bloom when deep in Alert (near-out with time left). Opt-in. | future |
| **Nudge** | A coaching notification (e.g. context-rot tip, "switch to a lighter model"). Calm, once-per-trigger. | future |
| **Prime** | The window-priming action — fire a tiny primer to align the 5-hr window with peak hours. | future |
| **Refill** | The reset moment — a brief Calm flash / "topped up" cue when the window resets. | future |
| **Dim/Bright** | Adaptive glow brightness — the Halo/Bloom rests **dim** (calm, easy on the eyes) and blooms **bright** on hover/activity, then eases back; Alert holds a higher dim floor. | locked |
| **HUD** | The menu-bar LED's hover pill — a custom numbers readout (`% used · resets · wk %`) shown on hover; click opens the menu. | locked |

## States (color = meaning)

| State | Color | Meaning |
|---|---|---|
| **Calm** | green `#30D158` | Healthy — plenty of runway. |
| **Watch** | amber `#FFD60A` | Pay attention — getting into the window. |
| **Alert** | red `#FF453A` | Near / at the limit, *or* burning fast enough to run out before reset. |
| **Idle** | gray `#8C8C8C` | No fresh data / window reset / waiting for Claude Code. |

**Color model** = risk of getting blocked *before reset*, not raw depletion: usage × time-left
(relaxes as reset nears) × burn-rate projection. Burn only *escalates* color once real depletion
exists (≥45% used, ramping to 75%) — a fresh window can never be Alert. Driven by the **5-hour
window only**; the 7-day weekly figure is shown in the dropdown/Readout, never in the glow
color. The context-rot warning fires at **40%**. Stale cache / passed reset → Idle. Reset time
is displayed in **IST** for now (configurable timezone deferred).

## Scenarios to always preview

- **Fresh window** (2% used, hours left) → must be **Calm**, never Alert. *(regression: see below)*
- **Mid-window steady** (~60%, few hours left) → Watch.
- **Near limit** (>90%) → Alert; if reset is minutes away, relax toward Watch (refill imminent).
- **Burning fast** (rising quickly, ≥45% used) → Alert + `↑` on the Readout.
- **Idle / waiting** (no cache yet, or reset passed) → gray, `waiting for Claude Code…`.
- **Reset moment** → Refill cue (future).

## Issues to iron out (running log)

- [x] **False-Alert on fresh window** (red at 2%): burn over-projected from a tiny early sample.
      Fixed — burn needs ≥3 samples over ≥10 min, and color escalation is gated to ≥45% used
      (ramp to 75%). Keep this scenario as a permanent regression check.
- [ ] **Halo z-order vs menu bar** — confirm the Halo never renders *behind* the system menu
      bar; bump window level if it clips.
- [ ] **Multi-display / clamshell / resolution change** — verify the overlay repositions to the
      correct (notched) screen and survives display reconfig.
- [ ] **Menu-bar overflow** — the LED can get hidden behind the notch when many menu extras are
      present (a macOS layout limit). Consider a `%`-text mode or documented guidance.
- [ ] **Non-notch Macs** — polish the fallback top-center Readout.
- [ ] **Timezone** — reset time is IST-hardcoded; make it configurable (v1.1).
- [ ] **Bleed bounds** — clamp the Readout so it never exceeds the overlay window / screen edge.
- [ ] **Idle detection tuning** — when exactly to gray out (stale cache vs genuine reset).
- [x] **Weekly in the glow** — resolved: color reflects the **5-hour only**; weekly stays in
      the dropdown.
- [~] **Color-blindness** (parked, not v1) — green/amber/red is the whole signal; a
      colorblind-safe palette / shape cue is a post-v1 consideration.
- [~] **Reduced motion** (parked, not v1) — respect `prefers-reduced-motion` / macOS "Reduce
      motion" for Breathe, Bleed, and the adaptive glow later.
- [x] **Adaptive-glow tuning** — agreed in `design/interactions.html` (dim floor ~30%, peak
      100%, hold ~1 min, fade ~1.4s, Alert floor ≥42%); carry to Swift.
- [ ] **Notch overlay** — click-through, z-order above the menu bar, full-screen/Spaces
      behavior, and not appearing in screen recordings.
