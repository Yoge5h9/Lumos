#if canImport(AppKit)
import AppKit

/// The **Readout** pill: `NN% used · resets H:MM AM/PM IST · wk NN%`, shown on
/// hover and animated with the **Bleed**. Ported from the `.pill` treatment in
/// `design/showcase.html` — the used-percentage is tinted with the state accent,
/// the reset is near-white, the weekly figure is dimmer.
final class ReadoutView: NSView {
    private let backdrop = PillChrome.makeBackdrop()
    private let label = NSTextField(labelWithString: "")

    private let horizontalPadding: CGFloat = 18
    private let verticalPadding: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byClipping
        addSubview(backdrop)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    /// Rebuild the pill contents and resize to fit. Returns the new size so the
    /// owning controller can position it (top-center, hanging below the notch).
    @discardableResult
    func update(fields: ReadoutFormatting.Fields, accent: NSColor) -> NSSize {
        label.attributedStringValue = attributed(fields: fields, accent: accent)
        label.sizeToFit()

        let size = NSSize(
            width: label.frame.width + horizontalPadding * 2,
            height: label.frame.height + verticalPadding * 2
        )
        setFrameSize(size)
        backdrop.frame = bounds
        label.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: label.frame.width,
            height: label.frame.height
        )
        return size
    }

    private func attributed(fields: ReadoutFormatting.Fields, accent: NSColor) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        let tabular = NSFont(descriptor: font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ]), size: 12.5) ?? font

        let result = NSMutableAttributedString()
        func append(_ text: String, _ color: NSColor, _ useTabular: Bool = false) {
            result.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color,
                .font: useTabular ? tabular : font
            ]))
        }
        let faint = NSColor.white.withAlphaComponent(0.4)

        if fields.isIdle {
            append(fields.primary, NSColor.white.withAlphaComponent(0.7))
            return result
        }

        append(fields.primary, accent, true)
        if let reset = fields.reset {
            append("   ·   ", faint)
            append(reset, NSColor.white.withAlphaComponent(0.85), true)
        }
        if let weekly = fields.weekly {
            append("   ·   ", faint)
            append(weekly, NSColor.white.withAlphaComponent(0.68), true)
        }
        return result
    }
}
#endif
