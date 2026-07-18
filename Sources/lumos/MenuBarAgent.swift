#if canImport(AppKit)
import AppKit
import LumosCore

/// Entry point for the GUI: builds an `NSApplication` as a menu-bar-only agent
/// (no dock icon) and runs its event loop. Called from `main.swift` when the
/// binary is invoked with no CLI subcommand.
func runMenuBarAgent() -> Never {
    let app = NSApplication.shared
    let delegate = MenuBarAgentDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    exit(0)
}

final class MenuBarAgentDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let settings = AppSettings.shared

    private var rootMenu: NSMenu?
    private let statusHeaderItem = NSMenuItem()
    private let weeklyItem = NSMenuItem()
    private let updateItem = NSMenuItem()

    private let notchController = NotchWindowController()
    private let hud = HUDPanel()
    private let onboarding = OnboardingController()

    /// The calm-contract notification brain. One instance, held for the app's
    /// lifetime; its state file location honors the same sandbox overrides as the
    /// rest of Lumos (default resolves under the cache dir).
    private let notificationEngine = NotificationEngine()

    /// The slowly-changing timing histogram, recomputed only on the coarse/wake
    /// ticks (see `pollNotifications`) and reused for the cheap cache-driven polls
    /// so `history.jsonl` is never re-streamed on every status-line tick.
    private var cachedTiming: TimingInsight?

    /// Held across refreshes so a burn-rate can accrue: each refresh records the
    /// latest 5-hour used% with a timestamp, and the least-squares slope over the
    /// recent window feeds `ColorModel` — this is what makes "burning fast →
    /// Alert" actually fire.
    private var burnSampler = BurnRateSampler()
    private let sampleRetention: TimeInterval = 30 * 60

    /// Sourced from the LumosCore updater (opt-in daily GitHub check); rendered on
    /// the "Update available" row and cleared to `.upToDate` otherwise.
    private var updateStatus: UpdateStatus = .upToDate
    var onUpgrade: (() -> Void)?

    private var menuIsOpen = false
    private var ledHoverMonitors: [Any] = []

    // MARK: - Lightweight scheduling (DECISIONS.md "zero idle overhead")

    /// Event-driven cache reads: a vnode monitor on the cache file wakes the
    /// pipeline only when the data actually changes, instead of a tight poll.
    private var cacheSource: DispatchSourceFileSystemObject?
    private var cacheWatchDescriptor: Int32 = -1
    private var watchDebounce: DispatchWorkItem?

    /// A COARSE, tolerance-relaxed tick — not a sub-minute busy loop — that drives
    /// only the transitions no data change signals: the cache going stale and a
    /// usage window resetting. Also the cadence the burn sampler needs to keep a
    /// rate fresh while a session sits idle between status-line ticks.
    private var coarseTimer: Timer?
    private var coarseTickCount = 0

    private var isPaused = false

    private var lastRender: RenderSignature?

    private static let coarseTickInterval: TimeInterval = 60
    /// Read `history.jsonl` for the Timing insight at most this often (in coarse
    /// ticks ≈ every 15 min): Timing notifications are daily-capped, so a sharper
    /// cadence would only burn I/O.
    private static let timingPollEveryNTicks = 15
    /// The window a "Quiet hours" toggle enables when no custom picker exists yet.
    private static let defaultQuietHours = QuietHours(startHour: 22, endHour: 8)

    private static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        statusItem.menu = buildMenu()

        installLEDHoverMonitors()
        onboarding.presentIfNeeded()

        // Persisted UI choices are the source of truth for the menu; push them into
        // the engine at launch so its decisions honor them even if its own state
        // file was reset.
        syncEngineFromSettings()

        onUpgrade = { [weak self] in self?.performUpgrade() }

        registerPowerObservers()
        startCacheWatch()
        startCoarseTick()

        // Initial paint + a full (timing-inclusive) poll so the first-run tip can
        // appear this session.
        recompute(source: .wake)
        applySurfaces()

        runUpdateCheckIfEnabled()
    }

    deinit {
        for monitor in ledHoverMonitors { NSEvent.removeMonitor(monitor) }
        stopCacheWatch()
        stopCoarseTick()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Recompute pipeline

    private enum RecomputeSource {
        /// The cache file changed on disk (a Claude Code status-line tick).
        case cacheChanged
        /// The coarse timer fired (stale/reset transitions + burn sampling).
        case coarseTick
        /// Launch or display wake — do the full, timing-inclusive catch-up.
        case wake
    }

    private func recompute(source: RecomputeSource) {
        let now = Date()
        let cache = CacheReader.loadTolerant(from: LumosPaths.cacheFile())
        let aggregate = CacheAggregator.aggregate(cache: cache, now: now)
        let freshness = aggregate.freshness(now: now)
        let burn = recordBurnSample(from: aggregate)

        paint(state: currentState(aggregate: aggregate, freshness: freshness, burn: burn, now: now),
              freshness: freshness, aggregate: aggregate, now: now)

        let includeTiming: Bool
        switch source {
        case .cacheChanged: includeTiming = false
        case .wake: includeTiming = true
        case .coarseTick: includeTiming = coarseTickCount % Self.timingPollEveryNTicks == 0
        }
        pollNotifications(cache: cache, now: now, includeTiming: includeTiming)
    }

    /// Re-render LED + Halo from the current cache without recording a burn sample
    /// or polling notifications — for menu toggles that change appearance only.
    private func repaintFromToggles() {
        let now = Date()
        let cache = CacheReader.loadTolerant(from: LumosPaths.cacheFile())
        let aggregate = CacheAggregator.aggregate(cache: cache, now: now)
        let freshness = aggregate.freshness(now: now)
        paint(state: currentState(aggregate: aggregate, freshness: freshness,
                                  burn: burnSampler.burnRatePerSecond(), now: now),
              freshness: freshness, aggregate: aggregate, now: now)
    }

    /// The base hue for the current reading. Stale freezes onto the last-known
    /// hue (the UI greys/dims it); Refilled reads calm from the clock; Waiting
    /// and master-off are Idle.
    private func currentState(aggregate: CacheAggregate, freshness: Freshness,
                              burn: Double?, now: Date) -> UsageState {
        guard !settings.masterOff else { return .idle }
        switch freshness {
        case .waiting: return .idle
        case .refilled: return .calm
        case .stale: return ColorModel.lastKnownState(aggregate: aggregate, now: now)
        case .live: return ColorModel.state(aggregate: aggregate, now: now, burnRatePerSecond: burn)
        }
    }

    private func paint(state: UsageState, freshness: Freshness, aggregate: CacheAggregate, now: Date) {
        // Nothing to "rest on" reads as no-signal, not Stale: master-off, or a
        // stale snapshot with no 5-hour numbers to freeze (e.g. a free plan).
        let effectiveFreshness: Freshness
        if settings.masterOff {
            effectiveFreshness = .waiting
        } else if freshness == .stale, state == .idle {
            effectiveFreshness = .waiting
        } else {
            effectiveFreshness = freshness
        }
        renderLED(state: state, freshness: effectiveFreshness, aggregate: aggregate, now: now)
        notchController.update(state: state, freshness: effectiveFreshness, aggregate: aggregate)
    }

    /// The LED image + optional "% text" the status item shows. Skipped entirely
    /// when nothing visible changed, so a coarse tick that re-reports the same
    /// state never repaints the menu bar.
    private struct RenderSignature: Equatable {
        let state: UsageState
        let freshness: Freshness
        let colored: Bool
        let title: String
    }

    private func renderLED(state: UsageState, freshness: Freshness, aggregate: CacheAggregate, now: Date) {
        let showColor = settings.ledColorEnabled && !settings.masterOff
        let isStale = freshness == .stale

        let title: String
        let resolved = ReadoutFormatting.resolved(for: aggregate, freshness: freshness)
        if settings.showPercentEnabled, let used = resolved.usedPercentage {
            title = " \(Int(used.rounded()))%"
        } else {
            title = ""
        }

        let signature = RenderSignature(state: state, freshness: freshness, colored: showColor, title: title)
        guard signature != lastRender else { return }
        lastRender = signature

        let ledColor = isStale ? state.color.staled() : state.color
        statusItem.button?.image = StatusItemLED.image(
            color: ledColor,
            monochrome: !showColor,
            opacity: isStale ? StaleStyle.glowLevel : 1
        )
        statusItem.button?.title = title
    }

    /// Record the current 5-hour used% (when fresh), prune to the recent window,
    /// and return the trusted burn-rate (or nil when there isn't enough signal).
    private func recordBurnSample(from aggregate: CacheAggregate) -> Double? {
        guard !aggregate.isStale,
              let used = aggregate.latestSnapshot?.fiveHour?.usedPercentage else {
            return nil
        }
        burnSampler.record(usedPercentage: used, at: Date())

        let cutoff = Date().addingTimeInterval(-sampleRetention)
        let recent = burnSampler.samples.filter { $0.timestamp >= cutoff }
        if recent.count != burnSampler.samples.count {
            burnSampler = BurnRateSampler(samples: recent)
        }
        return burnSampler.burnRatePerSecond()
    }

    /// Apply surface visibility (notch Halo / thin bar) from the current toggles.
    private func applySurfaces() {
        notchController.applyVisibility(
            notchGlowEnabled: settings.notchGlowEnabled && !settings.masterOff,
            thinBarEnabled: settings.thinBarEnabled
        )
    }

    // MARK: - Notification engine (the delivery seam)

    /// Runs the calm-contract engine and, if a notification is due, renders it as
    /// a pill. Context rides every recompute (cheap — no file read); Timing/Tip
    /// only need the timing histogram, which is refreshed on the coarse cadence.
    private func pollNotifications(cache: LumosCache, now: Date, includeTiming: Bool) {
        guard !settings.masterOff else { return }

        if includeTiming || cachedTiming == nil {
            cachedTiming = TimingAnalyzer.analyze(historyFile: LumosPaths.historyFile())
        }
        guard let timing = cachedTiming else { return }

        let signal = UsageSignal.fromCache(cache, now: now)
        guard let due = notificationEngine.poll(now: now, signal: signal, timing: timing) else { return }

        deliver(Self.pending(from: due), onDontShowAgain: { [weak self] in
            self?.notificationEngine.dontShowAgain(id: due.id)
        })
    }

    /// Map the engine's decision onto the UI value the pill renders. Accent is
    /// left to the per-kind default (Context `#FFD60A`, Timing `#64D2FF`, Tip
    /// `#BF5AF2`) so a pill's color signals its type.
    private static func pending(from due: DueNotification) -> PendingNotification {
        let kind: PendingNotification.Kind
        switch due.kind {
        case .context: kind = .context
        case .timing: kind = .timing
        case .tip: kind = .tip
        }
        return PendingNotification(kind: kind, title: due.title, body: due.body)
    }

    /// The delivery seam: render a due notification as a notch pill. Dismiss just
    /// closes; "Don't show again" first tells the engine to mute this exact id.
    func deliver(_ notification: PendingNotification, onDontShowAgain: (() -> Void)? = nil) {
        notchController.present(notification, onDontShowAgain: onDontShowAgain)
    }

    /// Push all persisted menu choices into the engine.
    private func syncEngineFromSettings() {
        notificationEngine.setMasterEnabled(!settings.masterOff)
        notificationEngine.setQuietHours(settings.quietHoursEnabled ? Self.defaultQuietHours : nil)
        notificationEngine.setType(.context, muted: settings.muteContext)
        notificationEngine.setType(.timing, muted: settings.muteTiming)
        notificationEngine.setType(.tip, muted: settings.muteTip)
    }

    // MARK: - Updater (the update seam)

    private func applyUpdateStatus(_ status: UpdateStatus) {
        updateStatus = status
    }

    /// The ONE optional network call Lumos makes, gated behind the opt-in setting.
    /// `checkForUpdate` throttles itself to once a day and records the attempt, so
    /// calling this on launch / on enable / on wake is safe.
    private func runUpdateCheckIfEnabled() {
        guard settings.updatesCheckEnabled else { return }
        let fetcher = GitHubReleaseFetcher(owner: "Yoge5h9", repo: "Lumos")
        let version = Self.currentVersion
        Task { [weak self] in
            do {
                if let status = try await UpdateChecker.checkForUpdate(currentVersion: version, fetcher: fetcher) {
                    let mapped: UpdateStatus
                    switch status {
                    case .upToDate: mapped = .upToDate
                    case let .available(version): mapped = .available(version: version)
                    }
                    await MainActor.run { [weak self] in self?.applyUpdateStatus(mapped) }
                }
            } catch {
                // Opt-in and calm: a flaky network never surfaces an error.
            }
        }
    }

    /// Run `brew upgrade lumos` then relaunch. The command is built by LumosCore;
    /// only the execution lives here.
    private func performUpgrade() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = UpdateChecker.upgradeCommand()

        var environment = ProcessInfo.processInfo.environment
        // A menu-bar/login-item agent can launch with a minimal PATH that omits
        // the Homebrew prefixes; ensure `brew` resolves.
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
            DispatchQueue.main.async { self?.relaunch() }
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Cache file watch

    private func startCacheWatch() {
        guard cacheSource == nil else { return }
        let path = LumosPaths.cacheFile().path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return } // file not there yet — the coarse tick retries

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let flags = source.data
            if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
                // Atomic replace: `AtomicFile` renames a temp over the cache, so our
                // descriptor now points at the old, unlinked inode — re-arm on the
                // replacement file.
                self.rearmCacheWatch()
            } else {
                self.scheduleCacheChanged()
            }
        }
        source.setCancelHandler { close(descriptor) }
        cacheSource = source
        cacheWatchDescriptor = descriptor
        source.resume()
    }

    private func stopCacheWatch() {
        watchDebounce?.cancel()
        watchDebounce = nil
        cacheSource?.cancel() // cancel handler closes the descriptor
        cacheSource = nil
        cacheWatchDescriptor = -1
    }

    private func rearmCacheWatch() {
        stopCacheWatch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isPaused else { return }
            self.startCacheWatch()
            self.recompute(source: .cacheChanged)
        }
    }

    /// Coalesce a burst of writes into a single recompute.
    private func scheduleCacheChanged() {
        watchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recompute(source: .cacheChanged) }
        watchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Coarse tick

    private func startCoarseTick() {
        guard coarseTimer == nil else { return }
        let timer = Timer(timeInterval: Self.coarseTickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.coarseTickCount &+= 1
            self.recompute(source: .coarseTick)
            // Pick up a cache file that didn't exist at launch (Lumos not wired yet).
            if self.cacheSource == nil { self.startCacheWatch() }
        }
        timer.tolerance = Self.coarseTickInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        coarseTimer = timer
    }

    private func stopCoarseTick() {
        coarseTimer?.invalidate()
        coarseTimer = nil
    }

    // MARK: - Display sleep / wake

    private func registerPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(displayDidSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func displayDidSleep() {
        guard !isPaused else { return }
        isPaused = true
        stopCacheWatch()
        stopCoarseTick()
    }

    @objc private func displayDidWake() {
        guard isPaused else { return }
        isPaused = false
        startCacheWatch()
        startCoarseTick()
        recompute(source: .wake) // catch up on anything missed while asleep
        runUpdateCheckIfEnabled()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rootMenu = menu

        statusHeaderItem.isEnabled = false
        weeklyItem.isEnabled = false
        menu.addItem(statusHeaderItem)
        menu.addItem(weeklyItem)
        menu.addItem(.separator())

        menu.addItem(toggleItem("Notch glow", action: #selector(toggleNotchGlow)))
        menu.addItem(toggleItem("Menu-bar LED", action: #selector(toggleLEDColor)))
        menu.addItem(toggleItem("Show % text", action: #selector(toggleShowPercent)))
        menu.addItem(toggleItem("Thin glow bar (no-notch Macs)", action: #selector(toggleThinBar)))
        menu.addItem(.separator())

        let notifications = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notifications.submenu = buildNotificationsSubmenu()
        menu.addItem(notifications)
        menu.addItem(.separator())

        menu.addItem(toggleItem("Check for updates", action: #selector(toggleUpdatesCheck)))
        updateItem.action = #selector(upgrade)
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        menu.addItem(.separator())

        menu.addItem(toggleItem("Launch at login", action: #selector(toggleLaunchAtLogin)))
        menu.addItem(toggleItem("Turn Lumos off", action: #selector(toggleMasterOff)))
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Lumos…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Lumos", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// A checkmark = "this is on". For the per-type rows, on means *not muted* —
    /// the user reads them as "show these", not "silence these".
    private func buildNotificationsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.delegate = self
        submenu.addItem(toggleItem("Quiet hours", action: #selector(toggleQuietHours)))
        submenu.addItem(.separator())
        submenu.addItem(toggleItem("Context alerts", action: #selector(toggleContextMute)))
        submenu.addItem(toggleItem("Timing insights", action: #selector(toggleTimingMute)))
        submenu.addItem(toggleItem("Pro tips", action: #selector(toggleTipMute)))
        return submenu
    }

    private func toggleItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === rootMenu {
            refreshHeaderAndUpdateRow(in: menu)
        }
        applyChecks(in: menu)
    }

    /// Refresh the on-demand text (header + weekly) and the update row right before
    /// the root menu opens.
    private func refreshHeaderAndUpdateRow(in menu: NSMenu) {
        let now = Date()
        let aggregate = CacheAggregator.loadAndAggregate(cacheFile: LumosPaths.cacheFile(), now: now)
        let freshness = aggregate.freshness(now: now)

        if freshness == .waiting {
            statusHeaderItem.title = "Waiting for Claude Code…"
            weeklyItem.isHidden = true
        } else {
            let resolved = ReadoutFormatting.resolved(for: aggregate, freshness: freshness)
            let usedText = resolved.usedPercentage.map { "\(Int($0.rounded()))% used" } ?? "usage unknown"
            let staleSuffix = freshness == .stale ? " (stale)" : ""
            statusHeaderItem.title = usedText + resetSuffix(resolved.resetEpoch) + staleSuffix

            if let weekly = aggregate.latestSnapshot?.sevenDay?.usedPercentage {
                weeklyItem.title = "Weekly: \(Int(weekly.rounded()))%"
                weeklyItem.isHidden = false
            } else {
                weeklyItem.isHidden = true
            }
        }

        switch updateStatus {
        case .upToDate:
            updateItem.isHidden = true
        case let .available(version):
            updateItem.title = "Update available (v\(version))"
            updateItem.isHidden = false
        }
    }

    private func applyChecks(in menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(toggleNotchGlow): item.state = settings.notchGlowEnabled ? .on : .off
            case #selector(toggleLEDColor): item.state = settings.ledColorEnabled ? .on : .off
            case #selector(toggleShowPercent): item.state = settings.showPercentEnabled ? .on : .off
            case #selector(toggleThinBar): item.state = settings.thinBarEnabled ? .on : .off
            case #selector(toggleQuietHours): item.state = settings.quietHoursEnabled ? .on : .off
            case #selector(toggleContextMute): item.state = settings.muteContext ? .off : .on
            case #selector(toggleTimingMute): item.state = settings.muteTiming ? .off : .on
            case #selector(toggleTipMute): item.state = settings.muteTip ? .off : .on
            case #selector(toggleUpdatesCheck): item.state = settings.updatesCheckEnabled ? .on : .off
            case #selector(toggleMasterOff): item.state = settings.masterOff ? .on : .off
            case #selector(toggleLaunchAtLogin): item.state = LaunchAtLogin.isEnabled ? .on : .off
            default: break
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        hud.hide()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func resetSuffix(_ resetsAt: Int64?) -> String {
        guard let resetsAt else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(resetsAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = ReadoutFormatting.indiaTimeZone
        return " · resets \(formatter.string(from: date)) IST"
    }

    // MARK: - LED hover → HUD (hover = glance, click = control)

    private func installLEDHoverMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.handleLEDHover() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { handler($0) }) {
            ledHoverMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { event in
            handler(event); return event
        }) {
            ledHoverMonitors.append(local)
        }
    }

    private func handleLEDHover() {
        guard !menuIsOpen, let anchor = ledScreenRect() else { hud.hide(); return }
        if anchor.contains(NSEvent.mouseLocation) {
            let now = Date()
            let aggregate = CacheAggregator.loadAndAggregate(cacheFile: LumosPaths.cacheFile(), now: now)
            let freshness = aggregate.freshness(now: now)
            let burn = burnSampler.burnRatePerSecond()
            let state = currentState(aggregate: aggregate, freshness: freshness, burn: burn, now: now)
            let fields = ReadoutFormatting.full(for: aggregate, freshness: freshness, now: now)
            let accent = freshness == .stale ? state.color.staled() : state.color
            hud.show(below: anchor, fields: fields, accent: accent)
        } else if hud.isVisible {
            hud.hide()
        }
    }

    private func ledScreenRect() -> CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }

    // MARK: - Toggle actions

    @objc private func toggleNotchGlow() { settings.notchGlowEnabled.toggle(); applySurfaces() }
    @objc private func toggleLEDColor() { settings.ledColorEnabled.toggle(); repaintFromToggles() }
    @objc private func toggleShowPercent() { settings.showPercentEnabled.toggle(); repaintFromToggles() }
    @objc private func toggleThinBar() { settings.thinBarEnabled.toggle(); applySurfaces() }

    @objc private func toggleQuietHours() {
        settings.quietHoursEnabled.toggle()
        notificationEngine.setQuietHours(settings.quietHoursEnabled ? Self.defaultQuietHours : nil)
    }

    @objc private func toggleContextMute() {
        settings.muteContext.toggle()
        notificationEngine.setType(.context, muted: settings.muteContext)
    }

    @objc private func toggleTimingMute() {
        settings.muteTiming.toggle()
        notificationEngine.setType(.timing, muted: settings.muteTiming)
    }

    @objc private func toggleTipMute() {
        settings.muteTip.toggle()
        notificationEngine.setType(.tip, muted: settings.muteTip)
    }

    @objc private func toggleUpdatesCheck() {
        settings.updatesCheckEnabled.toggle()
        if settings.updatesCheckEnabled { runUpdateCheckIfEnabled() }
    }

    @objc private func toggleMasterOff() {
        settings.masterOff.toggle()
        notificationEngine.setMasterEnabled(!settings.masterOff)
        repaintFromToggles()
        applySurfaces()
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !LaunchAtLogin.isEnabled
        LaunchAtLogin.setEnabled(target)
    }

    @objc private func showAbout() { onboarding.present() }

    @objc private func upgrade() { onUpgrade?() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
#endif
