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

        let mark = NSView()
        mark.wantsLayer = true
        mark.layer?.cornerRadius = 7
        let calm = NSColor(hex: "#30D158") ?? .systemGreen
        mark.layer?.backgroundColor = calm.cgColor
        mark.layer?.shadowColor = calm.cgColor
        mark.layer?.shadowRadius = 10
        mark.layer?.shadowOpacity = 0.9
        mark.layer?.shadowOffset = .zero
        mark.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 14),
            mark.heightAnchor.constraint(equalToConstant: 14)
        ])
        stack.addArrangedSubview(mark)
        stack.setCustomSpacing(18, after: mark)

        let title = label("Lumos", size: 22, weight: .semibold, color: .white)
        title.alignment = .center
        addFullWidth(title, to: stack)
        stack.setCustomSpacing(8, after: title)

        let subtitle = label(
            "A calm glow that shows how much of your Claude 5-hour window is left — at a glance, without opening anything.",
            size: 13, weight: .regular, color: NSColor.white.withAlphaComponent(0.6)
        )
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 0
        subtitle.preferredMaxLayoutWidth = contentWidth
        addFullWidth(subtitle, to: stack)
        stack.setCustomSpacing(22, after: subtitle)

        let bullets = [
            ("Local & private", "Reads Claude Code's status-line data on this Mac. No network, no accounts, no API keys."),
            ("Two surfaces", "A colored glow around the notch and a dot in the menu bar — green is healthy, red is near the limit."),
            ("You're in control", "Click the menu-bar dot to toggle surfaces, tune notifications, or quit. Hover it for the exact numbers.")
        ]
        for (heading, detail) in bullets {
            stack.addArrangedSubview(bulletRow(heading: heading, detail: detail))
        }

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
