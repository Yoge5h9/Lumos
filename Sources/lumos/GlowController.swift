#if canImport(AppKit)
import AppKit
import LumosCore

/// Drives the Halo/Bloom's **adaptive brightness** — "dim at rest, bright on
/// attention" — locked in `design/interactions.html`. The glow rests at a low
/// `dimFloor`, blooms to `peak` on hover or fresh activity, holds `brightHold`,
/// then eases back over `fadeDuration`. Alert keeps a higher `alertFloor` so a
/// near-limit glow never fully fades.
///
/// The values below are the agreed starting points from the signed-off demo,
/// carried to Swift as tunable defaults (DECISIONS.md "Locked — interactions").
final class GlowController {
    // MARK: - Tunable timings (from the signed-off interactions demo)
    var dimFloor: CGFloat = 0.30
    var peak: CGFloat = 1.0
    var alertFloor: CGFloat = 0.42
    var brightHold: TimeInterval = 60
    var fadeDuration: CFTimeInterval = 1.4
    var wakeDuration: CFTimeInterval = 0.5

    private weak var view: HaloView?
    private var state: UsageState = .idle
    private var holdWorkItem: DispatchWorkItem?
    private var isBright = false

    /// Stale is dead-still: while frozen the glow holds a fixed dim level and
    /// ignores wake/settle, so nothing breathes until fresh data arrives.
    private var isFrozen = false

    init(view: HaloView) {
        self.view = view
    }

    /// The resting brightness for the current state — lifted for Alert so a real
    /// warning keeps a visible ember while unattended.
    private var restingFloor: CGFloat {
        state == .alert ? max(dimFloor, alertFloor) : dimFloor
    }

    /// Update the state (color already applied by the caller). If the glow is
    /// currently at rest, reapply the resting floor so an Alert transition lifts
    /// the ember immediately.
    func setState(_ newState: UsageState) {
        state = newState
        if !isBright {
            view?.setGlowLevel(restingFloor, duration: 0.4)
        }
    }

    /// Hold a fixed, dimmed level with no motion (Stale). Eases in over
    /// `duration`, then stays put — `wake`/`settle` are inert until `unfreeze`.
    func freeze(at level: CGFloat, duration: CFTimeInterval) {
        holdWorkItem?.cancel()
        isBright = false
        isFrozen = true
        view?.setGlowLevel(level, duration: duration)
    }

    /// Leave the frozen Stale hold so the glow can respond to state/hover again.
    func unfreeze() {
        isFrozen = false
    }

    /// Bloom to peak, hold, then ease back to the resting floor.
    func wake() {
        guard !isFrozen else { return }
        holdWorkItem?.cancel()
        isBright = true
        view?.setGlowLevel(peak, duration: wakeDuration)

        let work = DispatchWorkItem { [weak self] in self?.settle() }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + brightHold, execute: work)
    }

    /// Ease from bright back down to the resting floor.
    func settle() {
        holdWorkItem?.cancel()
        isBright = false
        view?.setGlowLevel(restingFloor, duration: fadeDuration)
    }

    /// Snap to the resting floor with no bloom (used on first show).
    func forceRest() {
        holdWorkItem?.cancel()
        isBright = false
        view?.setGlowLevel(restingFloor, duration: 0)
    }
}
#endif
