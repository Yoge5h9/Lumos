#if canImport(AppKit)
import AppKit

/// A notification to render as a pill. This is the value the app renders; the
/// decision logic that produces it (the calm-contract engine — caps, quiet
/// hours, de-dupe, "don't show again") lives in the LumosCore notification
/// engine, not here.
struct PendingNotification {
    enum Kind {
        case context, timing, tip

        /// The type accent (deliberately separate from the Calm/Watch/Alert state
        /// palette): Context amber, Timing cyan, Tip purple — DECISIONS.md.
        var defaultAccentHex: String {
            switch self {
            case .context: return "#FFD60A"
            case .timing: return "#64D2FF"
            case .tip: return "#BF5AF2"
            }
        }

        var glyph: String {
            switch self {
            case .context: return "!"
            case .timing: return "◔"
            case .tip: return "✦"
            }
        }

        var tag: String {
            switch self {
            case .context: return "Context"
            case .timing: return "Timing"
            case .tip: return "Tip"
            }
        }
    }

    let kind: Kind
    let accentHex: String
    let title: String
    let body: String

    init(kind: Kind, accentHex: String? = nil, title: String? = nil, body: String) {
        self.kind = kind
        self.accentHex = accentHex ?? kind.defaultAccentHex
        self.title = title ?? kind.tag
        self.body = body
    }
}

/// Renders one `PendingNotification` as a dismissible pill that Bleeds from the
/// notch. Ported from `design/notifications.html`: an accent icon disc, a small
/// uppercase tag, the message, a hover-revealed "Don't show again", and a close
/// control.
final class NotificationPillView: NSView {
    static let width: CGFloat = 320

    var onDismiss: (() -> Void)?
    var onDontShowAgain: (() -> Void)?

    private let backdrop = PillChrome.makeBackdrop()
    private let iconContainer = NSView()
    private let iconLabel = NSTextField(labelWithString: "")
    private let tagLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let dontShowButton = NSButton()
    private let closeButton = NSButton()

    private var trackingArea: NSTrackingArea?

    init(notification: PendingNotification) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        build(notification: notification)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    private func build(notification: PendingNotification) {
        let accent = NSColor(hex: notification.accentHex) ?? .systemYellow

        addSubview(backdrop)

        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 12
        iconContainer.layer?.backgroundColor = accent.withAlphaComponent(0.15).cgColor
        addSubview(iconContainer)

        iconLabel.stringValue = notification.kind.glyph
        iconLabel.font = .systemFont(ofSize: 12, weight: .bold)
        iconLabel.textColor = accent
        iconLabel.alignment = .center
        iconContainer.addSubview(iconLabel)

        tagLabel.stringValue = notification.title.uppercased()
        tagLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tagLabel.textColor = accent
        addSubview(tagLabel)

        bodyLabel.stringValue = notification.body
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        bodyLabel.maximumNumberOfLines = 0
        addSubview(bodyLabel)

        configureTextButton(dontShowButton, title: "Don’t show again", size: 11,
                            color: NSColor.white.withAlphaComponent(0.5), action: #selector(dontShowAgain))
        dontShowButton.isHidden = true
        addSubview(dontShowButton)

        configureTextButton(closeButton, title: "✕", size: 12,
                            color: NSColor.white.withAlphaComponent(0.45), action: #selector(dismiss))
        closeButton.isHidden = true
        addSubview(closeButton)

        layoutPill()
    }

    private func configureTextButton(_ button: NSButton, title: String, size: CGFloat, color: NSColor, action: Selector) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.target = self
        button.action = action
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: size)
        ])
    }

    private func layoutPill() {
        let pad: CGFloat = 14
        let iconSize: CGFloat = 24
        let gap: CGFloat = 10
        let textX = pad + iconSize + gap
        let textWidth = Self.width - textX - pad - 8

        tagLabel.sizeToFit()
        bodyLabel.preferredMaxLayoutWidth = textWidth
        let bodySize = bodyLabel.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude))

        let tagH = tagLabel.frame.height
        let actionsH: CGFloat = 18
        let contentH = tagH + 3 + bodySize.height + actionsH
        let height = max(iconSize + pad, contentH + pad * 2 - 4) + 2

        setFrameSize(NSSize(width: Self.width, height: height))
        backdrop.frame = bounds

        iconContainer.frame = NSRect(x: pad, y: pad, width: iconSize, height: iconSize)
        iconLabel.frame = iconContainer.bounds

        var y = pad
        tagLabel.frame = NSRect(x: textX, y: y, width: textWidth, height: tagH)
        y += tagH + 3
        bodyLabel.frame = NSRect(x: textX, y: y, width: textWidth, height: bodySize.height)
        y += bodySize.height + 4
        dontShowButton.sizeToFit()
        dontShowButton.frame = NSRect(x: textX, y: y, width: dontShowButton.frame.width, height: actionsH)

        closeButton.sizeToFit()
        closeButton.frame = NSRect(x: Self.width - 22, y: 8, width: 16, height: 16)
    }

    // MARK: - Hover reveals the affordances

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
        dontShowButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
        dontShowButton.isHidden = true
    }

    @objc private func dismiss() { onDismiss?() }
    @objc private func dontShowAgain() { onDontShowAgain?() }
}
#endif
