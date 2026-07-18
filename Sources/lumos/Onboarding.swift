#if canImport(AppKit)
import AppKit

/// A single first-run window that explains, in plain words, what powers Lumos
/// (it reads Claude Code's local status-line data — no network, no API keys),
/// the surfaces it shows (the notch glow + the menu-bar dot), and where the
/// controls live (the menu-bar icon). Shown once; the "seen" flag lives in
/// `AppSettings`.
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings

    /// Width the body copy wraps within; the window height is derived from the
    /// laid-out content so nothing can clip or overlap regardless of copy length.
    private let contentWidth: CGFloat = 356
    private let horizontalPadding: CGFloat = 32

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    /// Show the window if the user hasn't seen it yet.
    func presentIfNeeded() {
        guard !settings.onboardingSeen else { return }
        present()
    }

    func present() {
        if let existing = window {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = makeContent()
        let fitting = content.fittingSize

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // ARC owns this window via `self.window`; leaving AppKit's default
        // release-on-close on would double-free it after `close()`.
        window.isReleasedWhenClosed = false
        window.title = "Welcome to Lumos"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentView = content
        window.setContentSize(fitting)
        window.center()
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.02, green: 0.02, blue: 0.024, alpha: 1).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: horizontalPadding, bottom: 28, right: horizontalPadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        let title = label("Lumos", size: 22, weight: .semibold, color: .white)
        header.addArrangedSubview(title)
        if let mark = OnboardingMark.image() {
            let markSize: CGFloat = 34
            let markView = NSImageView(image: mark)
            markView.imageScaling = .scaleProportionallyUpOrDown
            markView.translatesAutoresizingMaskIntoConstraints = false
            markView.widthAnchor.constraint(equalToConstant: markSize).isActive = true
            markView.heightAnchor.constraint(equalToConstant: markSize).isActive = true
            header.addArrangedSubview(markView)
        }
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(8, after: header)

        let subtitle = label(
            "Lumos lights up the dark — always see, at a glance, how much of your Claude 5-hour window is left.",
            size: 13, weight: .regular, color: NSColor.white.withAlphaComponent(0.6)
        )
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 0
        subtitle.preferredMaxLayoutWidth = contentWidth
        addFullWidth(subtitle, to: stack)
        stack.setCustomSpacing(22, after: subtitle)

        let bullets = [
            ("Two ways to see it", "A soft glow around the notch, and a dot in the menu bar. Calm green, warming to amber, then red as your window fills."),
            ("Tips worth knowing", "Every so often, a quiet notification with a Claude Code tip."),
            ("You're in control", "Everything lives in the menu-bar dot: toggle the notch or the dot, tune notifications, or quit. Hover for the exact numbers."),
            ("Local & private", "Reads Claude Code's status line on this Mac.")
        ]
        for (heading, detail) in bullets {
            stack.addArrangedSubview(bulletRow(heading: heading, detail: detail))
        }

        let note = label(
            "Updates only while you use Claude Code in the terminal.",
            size: 13, weight: .semibold, color: NSColor.white.withAlphaComponent(0.78)
        )
        note.alignment = .center
        note.maximumNumberOfLines = 0
        note.preferredMaxLayoutWidth = contentWidth
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last ?? note)
        addFullWidth(note, to: stack)

        let button = NSButton(title: "Got it", target: self, action: #selector(dismissOnboarding))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.setCustomSpacing(26, after: stack.arrangedSubviews.last ?? button)
        stack.addArrangedSubview(button)

        return root
    }

    /// A left-aligned heading + wrapping detail line, grouped so the two stay
    /// tightly spaced while the outer stack controls the gap between bullets.
    private func bulletRow(heading: String, detail: String) -> NSView {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 3

        let h = label(heading, size: 13, weight: .semibold, color: .white)
        let d = label(detail, size: 12, weight: .regular, color: NSColor.white.withAlphaComponent(0.55))
        d.maximumNumberOfLines = 0
        d.preferredMaxLayoutWidth = contentWidth

        group.addArrangedSubview(h)
        group.addArrangedSubview(d)
        addFullWidth(group, to: nil)
        return group
    }

    /// Pin a view's width to the wrapping content width so multi-line labels get
    /// a stable layout width (and thus a correct intrinsic height).
    private func addFullWidth(_ view: NSView, to stack: NSStackView?) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        if let stack { stack.addArrangedSubview(view) }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isEditable = false
        field.drawsBackground = false
        field.isBezeled = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    @objc private func dismissOnboarding() {
        settings.onboardingSeen = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        settings.onboardingSeen = true
        window = nil
    }
}
#endif
