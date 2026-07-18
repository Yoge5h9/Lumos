#if canImport(AppKit)
import AppKit
import LumosCore

/// Owns the borderless overlay window pinned around the notch and everything
/// drawn in it: the **Halo/Bloom** (adaptive-glow), the hover **Readout** (with
/// the **Bleed**), and the notification pill stack. On a non-notch Mac it renders
/// the optional thin top-center glow bar, or hides entirely (LED-only default).
///
/// Known-blocker dispositions (DECISIONS.md "Notch overlay window"):
/// - **Click-through vs hover:** the window stays click-through
///   (`ignoresMouseEvents = true`); hover is detected from cursor position via a
///   global/local mouse-moved monitor, so the overlay never steals a click. It
///   flips to interactive only while a dismissible notification pill is shown.
/// - **Z-order above the menu bar:** window level is one above `.mainMenu`.
/// - **All Spaces + full-screen:** `.canJoinAllSpaces` + `.fullScreenAuxiliary`.
/// - **Visible to screen capture:** `sharingType = .readOnly` (default) so the
///   glow can be screenshotted / recorded for demos and support.
final class NotchWindowController {
    private let dropHeight: CGFloat = 240

    private var panel: NSPanel!
    private var contentView: NSView!
    private let haloView = HaloView()
    private let readoutView = ReadoutView()
    /// The blended "stale · updated Xm ago" line, centered just below the Readout
    /// (never inline — that would widen the pill). Ambient, not a loud chip.
    private let staleSubLabel = NSTextField(labelWithString: "")
    private lazy var glow = GlowController(view: haloView)

    private var geometry = NotchGeometry.detect()
    private var currentAccent: NSColor = .systemGray
    private var currentAggregate: CacheAggregate?
    private var currentFreshness: Freshness = .waiting
    private var currentState: UsageState = .idle
    /// Mirrors the app's master toggle so the hover re-derive resolves the same
    /// effective freshness the paint pipeline did (see `refreshReadout`).
    private var currentMasterOff = false
    private var lastState: UsageState?
    private var lastFreshness: Freshness?
    private var isVisibleSurface = false

    private var pills: [NotificationPillView] = []

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var readoutVisible = false

    init() {
        buildWindow()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        installHoverMonitors()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Window

    private func buildWindow() {
        let frame = geometry.overlayWindowFrame(dropHeight: dropHeight)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .readOnly

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.masksToBounds = false
        panel.contentView = content
        contentView = content

        haloView.frame = content.bounds
        haloView.autoresizingMask = [.width, .height]
        content.addSubview(haloView)

        content.addSubview(readoutView)
        PillChrome.collapse(readoutView)

        staleSubLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        staleSubLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        staleSubLabel.alignment = .center
        staleSubLabel.isBezeled = false
        staleSubLabel.drawsBackground = false
        staleSubLabel.isEditable = false
        staleSubLabel.isSelectable = false
        staleSubLabel.isHidden = true
        content.addSubview(staleSubLabel)

        glow.forceRest()
    }

    // MARK: - Public API

    /// Push the latest state + numbers. `state` colors the Halo and sets the
    /// adaptive-glow's resting floor; `freshness` decides whether that hue reads
    /// full and live or desaturated-dimmed-and-frozen; `aggregate` feeds the
    /// Readout text.
    func update(state: UsageState, freshness: Freshness, aggregate: CacheAggregate, masterOff: Bool) {
        currentAggregate = aggregate
        currentState = state
        currentMasterOff = masterOff
        applyFreshness(freshness)
        if readoutVisible { refreshReadout() }
    }

    /// Color the Halo/Bloom for `freshness` (staled + frozen when stale, else the
    /// live hue). Animates ONLY when the state or freshness actually changes, so a
    /// coarse tick that re-reports the same reading never re-drives the glow (it
    /// stays a static CALayer at rest — DECISIONS.md "zero idle overhead").
    private func applyFreshness(_ freshness: Freshness) {
        currentFreshness = freshness
        let isStale = freshness == .stale
        currentAccent = currentState.accent(stale: isStale)

        if currentState != lastState || freshness != lastFreshness {
            let duration: CFTimeInterval = isStale ? StaleStyle.fadeDuration : 0.4
            haloView.setColor(currentAccent, animated: true, duration: duration)
            if isStale {
                glow.freeze(at: StaleStyle.glowLevel, duration: StaleStyle.fadeDuration)
            } else {
                glow.unfreeze()
                glow.setState(currentState)
            }
            lastState = currentState
            lastFreshness = freshness
        }
        refreshStaleLine()
    }

    /// Show/hide + pick the surface treatment for the current display. Non-notch +
    /// thin-bar-off hides the overlay (LED-only default).
    func applyVisibility(notchGlowEnabled: Bool, thinBarEnabled: Bool) {
        geometry = NotchGeometry.detect()
        let shouldShow = notchGlowEnabled && (geometry.hasNotch || thinBarEnabled)
        isVisibleSurface = shouldShow

        guard shouldShow else {
            staleSubLabel.isHidden = true
            panel.orderOut(nil)
            return
        }

        layoutForGeometry(thinBarEnabled: thinBarEnabled)
        panel.orderFrontRegardless()
        refreshStaleLine()
    }

    private func layoutForGeometry(thinBarEnabled: Bool) {
        let frame = geometry.overlayWindowFrame(dropHeight: dropHeight)
        panel.setFrame(frame, display: true)

        if geometry.hasNotch {
            haloView.configure(mode: .notch(
                width: geometry.notchFrame.width,
                height: geometry.renderNotchHeight,
                cornerRadius: geometry.cornerRadius
            ))
        } else {
            haloView.configure(mode: .thinBar(width: 184))
        }
        haloView.frame = contentView.bounds
        repositionPills()
    }

    @objc private func screenParametersChanged() {
        // Re-home to the (possibly new) notched screen and survive resolution /
        // clamshell / external-display reconfiguration.
        guard isVisibleSurface else { geometry = NotchGeometry.detect(); return }
        geometry = NotchGeometry.detect()
        layoutForGeometry(thinBarEnabled: haloIsThinBar)
        panel.orderFrontRegardless()
    }

    private var haloIsThinBar: Bool {
        !geometry.hasNotch
    }

    // MARK: - Hover → wake glow + Bleed the Readout

    private func installHoverMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }

    private var hoverRegionScreenRect: CGRect {
        // A forgiving band around the notch (or thin bar) so the glance wakes
        // without pixel-hunting.
        let notch = geometry.notchFrame
        return notch.insetBy(dx: -24, dy: -6)
    }

    private func handleMouseMoved() {
        guard isVisibleSurface else { return }
        let inRegion = hoverRegionScreenRect.contains(NSEvent.mouseLocation)
        if inRegion {
            // Re-derive freshness on every in-region move, not only the first: a
            // window that ages past the staleness threshold mid-hover must
            // desaturate and freeze at look-time, not wait for the next paint.
            // Ordered before wake() so a stale re-derivation freezes the glow and
            // the following wake is inert, leaving a stale hover dimmed.
            if pills.isEmpty {
                if readoutVisible { refreshReadout() } else { showReadout() }
            }
            glow.wake()
        } else if readoutVisible {
            hideReadout()
        }
    }

    private func showReadout() {
        refreshReadout()
        readoutVisible = true
        PillChrome.bleed(readoutView, visible: true)
    }

    private func hideReadout() {
        readoutVisible = false
        PillChrome.bleed(readoutView, visible: false)
        refreshStaleLine()
    }

    private func refreshReadout() {
        // Freshness is time-derived: it flips to .stale as the clock passes the
        // threshold with no new data. Re-derive it at look-time so the hover view
        // (Halo hue, pill, age line) is never staler than the menu — which
        // recomputes freshness live on open — between the coarse ticks that paint.
        // Resolve the SAME effective freshness the paint pipeline uses so the
        // notch, LED dot and menu never disagree, and the Halo never flips on a
        // hover that only re-derives raw age.
        if let aggregate = currentAggregate {
            let raw = aggregate.freshness(now: Date())
            let fresh = Freshness.effective(raw: raw, state: currentState, masterOff: currentMasterOff)
            if fresh != currentFreshness { applyFreshness(fresh) }
        }
        let fields = currentAggregate.map {
            ReadoutFormatting.compact(for: $0, freshness: currentFreshness)
        } ?? ReadoutFormatting.Fields(
            primary: ReadoutFormatting.waitingPrimary, reset: nil, weekly: nil, isIdle: true
        )
        let size = readoutView.update(fields: fields, accent: currentAccent)
        positionBelowNotch(readoutView, size: size, indexFromTop: 0)
        refreshStaleLine()
    }

    /// The ambient "stale · updated Xm ago" line, shown just below the Readout
    /// pill while hovering a stale window — immediately on hover, and refreshed on
    /// the coarse tick so its "Xm ago" keeps current. Hidden at rest and for any
    /// non-stale state (no permanent marker floating below the notch).
    private func refreshStaleLine() {
        let text = currentAggregate.flatMap {
            ReadoutFormatting.staleSubLabel(for: $0, freshness: currentFreshness)
        }
        guard readoutVisible, isVisibleSurface, let text else {
            staleSubLabel.isHidden = true
            return
        }
        staleSubLabel.stringValue = text
        staleSubLabel.sizeToFit()
        let gap: CGFloat = 5
        let originX = (contentView.bounds.width - staleSubLabel.frame.width) / 2
        let originY = readoutView.frame.minY - gap - staleSubLabel.frame.height
        staleSubLabel.setFrameOrigin(NSPoint(x: originX, y: originY))
        staleSubLabel.isHidden = false
    }

    // MARK: - Notification pills (rendered here; produced by LumosCore engine)

    /// Render a notification as a Bleed pill. Single-at-a-time: a new one
    /// replaces the current. The window becomes interactive while a pill is up so
    /// its close / "Don't show again" controls are clickable, then returns to
    /// click-through.
    func present(_ notification: PendingNotification, onDontShowAgain: (() -> Void)? = nil) {
        if readoutVisible { hideReadout() }
        clearPills()

        let pill = NotificationPillView(notification: notification)
        pill.onDismiss = { [weak self, weak pill] in self?.dismissPill(pill) }
        pill.onDontShowAgain = { [weak self, weak pill] in
            onDontShowAgain?()
            self?.dismissPill(pill)
        }
        contentView.addSubview(pill)
        pills.append(pill)

        // Size is intrinsic to the pill; position then Bleed in.
        positionBelowNotch(pill, size: pill.frame.size, indexFromTop: 0)
        PillChrome.collapse(pill)
        panel.ignoresMouseEvents = false
        PillChrome.bleed(pill, visible: true)

        if !isVisibleSurface {
            // Even LED-only users get the pill: show the overlay just for it.
            panel.orderFrontRegardless()
        }
    }

    private func dismissPill(_ pill: NotificationPillView?) {
        guard let pill else { return }
        PillChrome.bleed(pill, visible: false) { [weak self, weak pill] in
            pill?.removeFromSuperview()
            guard let self else { return }
            self.pills.removeAll { $0 === pill }
            if self.pills.isEmpty {
                self.panel.ignoresMouseEvents = true
                if !self.isVisibleSurface { self.panel.orderOut(nil) }
            }
        }
    }

    private func clearPills() {
        for pill in pills { pill.removeFromSuperview() }
        pills.removeAll()
        panel.ignoresMouseEvents = true
    }

    private func repositionPills() {
        for (index, pill) in pills.enumerated() {
            positionBelowNotch(pill, size: pill.frame.size, indexFromTop: index)
        }
    }

    /// Place a pill/readout centered horizontally with its top edge hanging just
    /// below the notch, stacked downward by index.
    private func positionBelowNotch(_ view: NSView, size: NSSize, indexFromTop: Int) {
        let gap: CGFloat = 10
        let belowNotchGap: CGFloat = 10
        let notchBottomY = contentView.bounds.maxY - geometry.renderNotchHeight - belowNotchGap
        var topY = notchBottomY
        for i in 0..<indexFromTop {
            let prior = (i < pills.count) ? pills[i].frame.height : size.height
            topY -= prior + gap
        }
        let originX = (contentView.bounds.width - size.width) / 2
        let originY = topY - size.height
        view.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
#endif
