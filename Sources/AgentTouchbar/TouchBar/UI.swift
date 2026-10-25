import AgentTouchbarCore
import AppKit

/// Button with a closure callback. The Touch Bar delivers touches to controls, not gesture recognizers,
/// so all interaction goes through buttons.
@MainActor
final class ActionButton: NSButton {
    var handler: (() -> Void)?

    convenience init(title: String, icon: NSImage? = nil, color: NSColor? = nil, handler: (() -> Void)? = nil) {
        self.init(frame: .zero)
        self.title = title
        self.image = icon
        self.imagePosition = icon == nil ? .noImage : (title.isEmpty ? .imageOnly : .imageLeading)
        self.bezelStyle = .rounded
        self.bezelColor = color
        self.handler = handler
        self.target = self
        self.action = #selector(fire)
        self.font = .systemFont(ofSize: UI.fontSize, weight: .medium)
        self.translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc private func fire() { handler?() }

    /// Borderless button, used for tappable text.
    func plain() -> ActionButton {
        isBordered = false
        return self
    }
}

@MainActor
enum UI {
    static var fontSize: CGFloat = 13
    static var spacing: CGFloat = 12
    static var accent: NSColor = .systemPurple

    static func apply(_ theme: Theme) {
        fontSize = theme.fontSize
        spacing = theme.spacing
        accent = NSColor.from(theme.accent, fallback: .systemPurple)
    }

    static func label(
        _ text: String = "", size: CGFloat? = nil, weight: NSFont.Weight = .medium,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedDigitSystemFont(ofSize: size ?? fontSize, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    static func imageView(_ image: NSImage?, tint: NSColor? = nil, size: CGFloat = 18) -> NSImageView {
        let view = NSImageView()
        view.image = image
        view.contentTintColor = tint
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }

    static func row(_ views: [NSView], spacing: CGFloat? = nil) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing ?? self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.required, for: .horizontal)
        return stack
    }

    /// Two lines of small text, suited to the right-hand status area.
    static func twoLines(_ top: String, _ bottom: String, color: NSColor = .labelColor) -> NSTextField {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let text = NSMutableAttributedString(
            string: top + "\n",
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        text.append(
            NSAttributedString(
                string: bottom,
                attributes: [
                    .font: font, .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ]))
        let field = NSTextField(labelWithAttributedString: text)
        field.maximumNumberOfLines = 2
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

/// Thin progress bar.
@MainActor
final class ProgressBar: NSView {
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    var color: NSColor = .systemPurple { didSet { needsDisplay = true } }

    init(width: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        var filled = bounds
        filled.size.width = bounds.width * CGFloat(min(1, max(0, fraction)))
        guard filled.width > 0 else { return }
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
